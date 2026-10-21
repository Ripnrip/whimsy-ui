import Foundation
import Testing
@testable import WhimsyCore

@Suite("WhimsySpring and WhimsyMath")
struct WhimsySpringTests {
    @Test func underdampedSpringOvershootsThenSettles() {
        var s = WhimsySpring(value: 0, stiffness: 170, dampingRatio: 0.4)
        var peak = 0.0
        for _ in 0..<240 { s.step(toward: 1, dt: 1.0 / 60); peak = max(peak, s.value) }
        #expect(peak > 1.15)
        #expect(s.isSettled(at: 1, tolerance: 1e-3))
    }

    @Test func criticallyDampedSpringNeverOvershoots() {
        var s = WhimsySpring(value: 0, stiffness: 300, dampingRatio: 1)
        for _ in 0..<120 { s.step(toward: 1, dt: 1.0 / 60); #expect(s.value <= 1 + 1e-9) }
        #expect(abs(s.value - 1) < 1e-3)
    }

    @Test func stepIgnoresBadInputAndClampsLongFrames() {
        var s = WhimsySpring(value: 0.5, stiffness: 100, dampingRatio: 0.7)
        let before = s
        s.step(toward: .nan, dt: 1 / 60); s.step(toward: 1, dt: 0); s.step(toward: 1, dt: -1); s.step(toward: 1, dt: .infinity)
        #expect(s == before)
        var a = s, b = s
        a.step(toward: 1, dt: 5)       // a stalled frame...
        b.step(toward: 1, dt: WhimsySpring.maxFrame)
        #expect(a == b)                // ...is integrated as at most 0.1 s
    }

    @Test func frameRateIndependent() {
        var a = WhimsySpring(stiffness: 200, dampingRatio: 0.5), b = a
        for _ in 0..<60 { a.step(toward: 1, dt: 1.0 / 60) }
        for _ in 0..<240 { b.step(toward: 1, dt: 1.0 / 240) }
        #expect(abs(a.value - b.value) < 1e-9)
    }

    @Test func stepResponseMatchesIntegratorAndLimits() {
        for z in [0.3, 1.0, 1.6] {
            #expect(WhimsySpring.stepResponse(at: 0, stiffness: 150, dampingRatio: z) == 0)
            #expect(abs(WhimsySpring.stepResponse(at: 10, stiffness: 150, dampingRatio: z) - 1) < 1e-6)
            var s = WhimsySpring(value: 0, stiffness: 150, dampingRatio: z)
            for _ in 0..<(240 * 3 / 10) { s.step(toward: 1, dt: 1.0 / 240) }   // 0.3 s
            #expect(abs(s.value - WhimsySpring.stepResponse(at: 0.3, stiffness: 150, dampingRatio: z)) < 0.02)
        }
        #expect(WhimsySpring.stepResponse(at: .infinity, stiffness: 1, dampingRatio: 0.5) == 1)
    }

    @Test func spring2DMovesBothAxes() {
        var p = WhimsySpring2D(value: .zero, stiffness: 200, dampingRatio: 1)
        for _ in 0..<120 { p.step(toward: Vec2(10, -4), dt: 1.0 / 60) }
        #expect(p.isSettled(at: Vec2(10, -4), tolerance: 1e-2))
        p.snap(to: Vec2(1, 2))
        #expect(p.value == Vec2(1, 2) && p.velocity == .zero)
    }

    @Test func mathHelpers() {
        #expect(WhimsyMath.clamp01(-1) == 0 && WhimsyMath.clamp01(2) == 1)
        #expect(WhimsyMath.lerp(2, 4, 0.25) == 2.5)
        #expect(WhimsyMath.progress(5, from: 0, to: 10) == 0.5)
        #expect(WhimsyMath.progress(1, from: 2, to: 2) == 0 && WhimsyMath.progress(3, from: 2, to: 2) == 1)
        #expect(WhimsyMath.smoothstep(0, 1, 0.5) == 0.5)
        #expect(WhimsyMath.easeInOutCubic(0) == 0 && WhimsyMath.easeInOutCubic(1) == 1 && WhimsyMath.easeInOutCubic(0.5) == 0.5)
        #expect(WhimsyMath.easeOutCubic(0.5) == 0.875)
    }
}
