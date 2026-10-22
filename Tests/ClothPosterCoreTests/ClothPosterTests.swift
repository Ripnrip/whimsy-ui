import Foundation
import Testing
@testable import ClothPosterCore

private func run(_ m: inout ClothModel, _ seconds: Double, _ each: (ClothModel) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * 60).rounded()) { m.step(1.0 / 60); each(m) }
}

@Suite("Wave")
struct WaveTests {
    let w = ClothWave()

    @Test func derivedConstants() {
        #expect(abs(w.wavenumber - 2 * .pi / 52) < 1e-12)
        #expect(abs(w.angularFrequency - w.wavenumber * 230) < 1e-9)
        #expect(abs(w.period - 52.0 / 230) < 1e-12)
    }

    @Test func silentBeyondTheFrontAndBeforeStart() {
        #expect(w.height(distance: 50, time: 0) == 0)
        #expect(w.height(distance: 50, time: -1) == 0)
        let t = 0.5, front = 230 * t
        #expect(w.height(distance: front + 1, time: t) == 0)
        #expect(w.height(distance: front + 200, time: t) == 0)
        #expect(w.gate(distance: front - 36 - 1, time: t) == 1)
        #expect(w.gate(distance: front - 18, time: t) > 0.4 && w.gate(distance: front - 18, time: t) < 0.6)
        #expect(w.height(distance: .nan, time: t) == 0)
    }

    @Test func travelsOutwardAtTheWaveSpeed() {
        // Behind the front, the pattern at (d, t) reappears at (d + c·Δt, t + Δt), scaled by the decay.
        let t = 1.0, dt = 0.1, d = 40.0
        let a = w.height(distance: d, time: t), b = w.height(distance: d + 230 * dt, time: t + dt)
        #expect(abs(b - a * exp(-230 * dt / 240)) < 1e-9)
        // Periodic in time at a fixed point well behind the front.
        #expect(abs(w.height(distance: d, time: t) - w.height(distance: d, time: t + w.period)) < 1e-9)
    }

    @Test func decaysWithDistance() {
        let t = 3.0
        let near = (0..<52).map { abs(w.height(distance: 10 + Double($0), time: t)) }.max()!
        let far = (0..<52).map { abs(w.height(distance: 250 + Double($0), time: t)) }.max()!
        #expect(far < near * 0.4)
        #expect(near <= 1)
    }

    @Test func slopeMatchesTheAnalyticDerivativeBehindTheFront() {
        let t = 2.0
        for d in stride(from: 5.0, to: 200, by: 13) {
            let phase = w.wavenumber * d - w.angularFrequency * t, e = exp(-d / 240)
            let analytic = w.wavenumber * cos(phase) * e - sin(phase) * e / 240
            #expect(abs(w.slope(distance: d, time: t) - analytic) < 2e-4, "d \(d)")
        }
        #expect(w.slope(distance: 0, time: t).isFinite)
    }

    @Test func crestsAreCountedOncePerPeriod() {
        #expect(w.crestIndex(time: 0) == 0)
        #expect(w.crestIndex(time: w.period * 0.99) == 0)
        #expect(w.crestIndex(time: w.period * 1.01) == 1)
        #expect(w.crestIndex(time: w.period * 10.5) == 10)
        #expect(w.crestIndex(time: .infinity) == 0)
    }
}

@Suite("Shading")
struct ShadingTests {
    @Test func flatClothHasNoSheenOrShade() {
        #expect(ClothShading.sheen(gradient: .zero) == 0)
        #expect(abs(ClothShading.shade(gradient: .zero)) < 1e-12)
        let n = ClothShading.normal(gradient: .zero)
        #expect(n.x == 0 && n.y == 0 && n.z == 1)
    }

    @Test func slopesFacingTheLightShine() {
        // The light is up-left, so a surface rising to the lower right faces it.
        let toward = Vec2(0.3, 0.4), away = Vec2(-0.3, -0.4)
        #expect(ClothShading.sheen(gradient: toward) > 0.2)
        #expect(ClothShading.sheen(gradient: away) == 0)
        #expect(ClothShading.shade(gradient: toward) > 0)
        #expect(ClothShading.shade(gradient: away) < 0)
        for g in [Vec2(5, 5), Vec2(-3, 9), Vec2(0.1, -0.2)] {
            let s = ClothShading.sheen(gradient: g)
            #expect(s >= 0 && s <= 1)
            let n = ClothShading.normal(gradient: g)
            #expect(abs(n.x * n.x + n.y * n.y + n.z * n.z - 1) < 1e-12)
        }
    }
}

@Suite("Cloth model")
struct ClothModelTests {
    @Test func stillUntilTouched() {
        var m = ClothModel()
        run(&m, 1)
        #expect(m.isSettled && m.amplitude.value == 0 && m.emitTime == 0 && m.tickCount == 0)
        #expect(m.sourcePosition(for: Vec2(10, 10)) == Vec2(10, 10))
    }

    @Test func holdingRipplesAtBaseAmplitudeAndTicksPerCrest() {
        var m = ClothModel()
        m.touchDown(at: Vec2(100, 100))
        run(&m, 2)
        #expect(abs(m.amplitude.value - 3.5) < 0.05)
        let crests = m.tuning.wave.crestIndex(time: m.emitTime)
        #expect(m.tickCount >= crests - 1 && m.tickCount <= crests)
        #expect(m.tickCount >= 7)
        #expect(m.height(at: Vec2(500, 500)) == 0, "566 pt away is still beyond the 460 pt front")
    }

    @Test func dragSpeedRaisesAmplitudeUpToTheCap() {
        var m = ClothModel()
        m.touchDown(at: Vec2(0, 200))
        var peak = 0.0
        for i in 1...60 { m.touchMoved(to: Vec2(Double(i) * 10, 200)); m.step(1.0 / 60); peak = max(peak, m.amplitude.value) }  // 600 pt/s
        #expect(abs(m.speed - 600) < 30)
        #expect(peak > 7.5 && peak <= 10 * 1.05)
        var n = ClothModel()
        n.touchDown(at: Vec2(0, 200))
        for i in 1...60 { n.touchMoved(to: Vec2(Double(i) * 60, 200)); n.step(1.0 / 60) }  // 3600 pt/s
        #expect(abs(n.amplitudeTarget - 10) < 1e-12)
        #expect(m.touch == Vec2(600, 200))
    }

    @Test func releaseRingsDownThroughFlatAndSettles() {
        var m = ClothModel()
        m.touchDown(at: Vec2(100, 100))
        run(&m, 1)
        m.touchUp()
        var negative = false, settledAt: Double?
        var t = 0.0
        run(&m, 4) { s in t += 1.0 / 60; if s.amplitude.value < -0.3 { negative = true }; if settledAt == nil && s.isSettled { settledAt = t } }
        #expect(negative, "the damped spring overshoots through flat")
        #expect(settledAt != nil && settledAt! < 4)
        #expect(m.amplitude.value == 0)
        let frozen = m.emitTime
        run(&m, 0.5)
        #expect(m.emitTime == frozen, "time stops once settled")
    }

    @Test func ticksStopAsTheRippleDiesAndAreRateLimited() {
        var m = ClothModel()
        m.touchDown(at: Vec2(100, 100))
        run(&m, 1)
        m.touchUp()
        let atRelease = m.tickCount
        run(&m, 4)
        let after = m.tickCount - atRelease
        #expect(after <= 3)
        var tuning = ClothModel.Tuning(); tuning.tickInterval = 0.5
        var r = ClothModel(tuning: tuning)
        r.touchDown(at: .zero)
        run(&r, 2)
        #expect(r.tickCount <= 4)
        #expect(r.lastTickStrength > 0.3 && r.lastTickStrength <= 1)
    }

    @Test func retouchingWhileRingingKeepsTheWavesTravelling() {
        var m = ClothModel()
        m.touchDown(at: Vec2(50, 50)); run(&m, 1); m.touchUp(); run(&m, 0.3)
        let t = m.emitTime
        m.touchDown(at: Vec2(80, 80))
        #expect(m.emitTime == t)
        m.touchUp(); run(&m, 6)
        m.touchDown(at: Vec2(80, 80))
        #expect(m.emitTime == 0, "a settled cloth starts a fresh ripple")
    }

    @Test func displacementIsRadialAndBoundedByAmplitude() {
        var m = ClothModel()
        m.touchDown(at: Vec2(150, 200))
        for i in 1...30 { m.touchMoved(to: Vec2(150 + Double(i) * 8, 200)); m.step(1.0 / 60) }
        let c = m.touch
        var maxShift = 0.0
        for x in stride(from: 0.0, to: 324, by: 17) { for y in stride(from: 0.0, to: 444, by: 19) {
            let p = Vec2(x, y), s = m.sourcePosition(for: p), shift = s - p
            maxShift = max(maxShift, shift.length)
            #expect(abs(shift.cross(p - c)) < 1e-6, "radial")
            #expect(abs(shift.length - abs(m.height(at: p))) < 1e-9)
            let sh = m.sheen(at: p)
            #expect(sh >= 0 && sh <= 1)
        } }
        #expect(maxShift > 1 && maxShift <= m.amplitude.value + 1e-9)
        #expect(m.sourcePosition(for: c) == c)
    }

    @Test func reduceMotionShrinksTheRippleAndDoesNotRing() {
        var m = ClothModel()
        m.reduceMotion = true
        m.touchDown(at: .zero); run(&m, 1)
        #expect(abs(m.effectiveAmplitude - 3.5 * 0.3) < 0.05)
        m.touchUp()
        var negative = false
        run(&m, 3) { if $0.amplitude.value < -1e-6 { negative = true } }
        #expect(!negative && m.isSettled)
    }

    @Test func ignoresNonFiniteInput() {
        var m = ClothModel()
        m.touchDown(at: Vec2(.nan, 1))
        #expect(!m.isTouching)
        m.touchDown(at: Vec2(10, 10)); m.touchMoved(to: Vec2(.infinity, 0))
        #expect(m.touch == Vec2(10, 10))
        m.step(.nan); m.step(-1)
        #expect(m.emitTime == 0)
    }
}
