import Testing
import Foundation
@testable import AliveEyesCore

private let h = 1.0 / 240

@Suite("Saccades")
struct SaccadeTests {
    @Test func intervalsAndOffsetsStayInRange() {
        var rng = SeededRandom(seed: 7)
        var s = SaccadeScheduler(rng: &rng)
        var last = s.offset, lastTime = 0.0, t = 0.0
        var gaps: [Double] = []
        for _ in 0..<(240 * 60) {
            s.step(dt: h, rng: &rng); t += h
            if s.offset != last {
                if lastTime > 0 { gaps.append(t - lastTime) }
                lastTime = t; last = s.offset
                #expect(SaccadeScheduler.rangeX.contains(s.offset.x) && SaccadeScheduler.rangeY.contains(s.offset.y))
            }
        }
        #expect(gaps.count > 60)
        #expect(gaps.allSatisfy { $0 >= 0.25 - 2 * h && $0 <= 0.9 + 2 * h })
        #expect(abs(gaps.reduce(0, +) / Double(gaps.count) - 0.575) < 0.06)
    }

    @Test func disabledMeansStill() {
        var rng = SeededRandom(seed: 7)
        var s = SaccadeScheduler(rng: &rng)
        for _ in 0..<480 { s.step(dt: h, rng: &rng) }
        s.isEnabled = false
        #expect(s.offset == .zero)
        let count = s.count
        for _ in 0..<2400 { s.step(dt: h, rng: &rng) }
        #expect(s.count == count && s.offset == .zero)
    }
}

@Suite("Blinks")
struct BlinkTests {
    @Test func curveShutsAt70msAndOpensBy170ms() {
        #expect(BlinkScheduler.closure(at: 0) == 0)
        #expect(BlinkScheduler.closure(at: 0.035) < 0.5)          // eases in
        #expect(abs(BlinkScheduler.closure(at: 0.0699999) - 1) < 1e-4)
        #expect(BlinkScheduler.closure(at: 0.070) == 1)
        #expect(BlinkScheduler.closure(at: 0.120) > 0.4 && BlinkScheduler.closure(at: 0.120) < 0.6)
        #expect(BlinkScheduler.closure(at: 0.170) == 0)
        // Half speed doubles both phases.
        #expect(BlinkScheduler.closure(at: 0.140, speed: 0.5) == 1)
        #expect(BlinkScheduler.closure(at: 0.339, speed: 0.5) > 0)
    }

    @Test func intervalsAndDoubleRateMatchTheArticle() {
        var rng = SeededRandom(seed: 42)
        var b = BlinkScheduler(rng: &rng)
        var starts: [Double] = []
        var wasBlinking = false, t = 0.0
        let seconds = 4000.0
        for _ in 0..<Int(seconds * 240) {
            b.step(dt: h, rng: &rng); t += h
            if b.isBlinking && !wasBlinking { starts.append(t) }
            wasBlinking = b.isBlinking
        }
        // Gaps between blink episodes (a double counts as one episode).
        let gaps = zip(starts, starts.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 >= 2.2 + 0.17 - 0.01 && $0 <= 6.5 + 0.48 + 0.01 })
        let episodes = Double(starts.count)
        let doubleRate = Double(b.doubleCount) / episodes
        #expect(abs(doubleRate - 0.18) < 0.04, "double rate \(doubleRate)")
        #expect(b.blinkCount == starts.count + b.doubleCount)
    }

    @Test func doubleBlinkSecondStarts240msLater() {
        var rng = SeededRandom(seed: 1)
        var b = BlinkScheduler(rng: &rng)
        b.blinkNow(double: true)
        var trace: [Double] = []
        for _ in 0..<Int(0.5 * 240) { b.step(dt: h, rng: &rng); trace.append(b.closure()) }
        // When each blink first passes 90% closed (a sample needn't land on the exact peak).
        let first = trace.firstIndex { $0 > 0.9 }!
        let second = trace.indices.first { $0 > first + 24 && trace[$0] > 0.9 }!
        #expect(abs(Double(second - first) * h - 0.240) < 2 * h)
        // Open between the two blinks.
        #expect(trace[Int(0.2 * 240)] == 0)
        #expect(!b.isBlinking && b.blinkCount == 2)
    }

    @Test func gentlerWithoutDoublesInReduceMotion() {
        var rng = SeededRandom(seed: 9)
        var b = BlinkScheduler(rng: &rng)
        b.speed = 0.5; b.allowsDoubles = false
        for _ in 0..<(240 * 600) { b.step(dt: h, rng: &rng) }
        #expect(b.blinkCount > 80 && b.doubleCount == 0)
    }
}

@Suite("Squint")
struct SquintTests {
    @Test func gentleMotionDoesNothing() {
        var s = SquintState()
        let triggered = s.feed(x: 0.3, y: 0.2, z: 0.9)  // |a| ≈ 0.99 g
        #expect(!triggered)
        #expect(s.level == 0)
    }

    @Test func shakeTriggersHoldsThenDecays() {
        var s = SquintState()
        let triggered = s.feed(x: 1.2, y: 0.9, z: 0.2)  // |a| ≈ 1.51 g
        #expect(triggered)
        #expect(s.level == 1)
        for _ in 0..<Int(0.5 * 240) { s.step(dt: h) }
        #expect(s.level == 1)                              // still holding
        for _ in 0..<Int(0.55 * 240) { s.step(dt: h) }
        #expect(s.level < 0.5 && s.level > 0.05)           // decaying
        for _ in 0..<(240 * 3) { s.step(dt: h) }
        #expect(s.level == 0)
    }

    @Test func decayIsFrameRateIndependent() {
        var a = SquintState(), b = SquintState()
        a.trigger(); b.trigger()
        for _ in 0..<60 { a.step(dt: 1.0 / 60) }
        for _ in 0..<240 { b.step(dt: 1.0 / 240) }
        #expect(abs(a.level - b.level) < 1e-9)
    }

    @Test func retriggerRefreshes() {
        var s = SquintState()
        s.trigger()
        for _ in 0..<240 { s.step(dt: h) }
        s.feed(x: 2, y: 0, z: 0)
        #expect(s.level == 1 && s.triggerCount == 2)
        let nanTriggered = s.feed(x: .nan, y: 0, z: 0)
        #expect(!nanTriggered)
    }
}
