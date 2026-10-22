import Foundation
import Testing
@testable import MoonPhaseCore

private func run(_ m: inout MoonScrubModel, _ seconds: Double, _ each: (MoonScrubModel) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * 60).rounded()) { m.step(1.0 / 60); each(m) }
}

@Suite("Phase maths")
struct MoonMathTests {
    @Test func wrapIntoUnitInterval() {
        #expect(MoonMath.wrap(0) == 0)
        #expect(abs(MoonMath.wrap(1.25) - 0.25) < 1e-12)
        #expect(abs(MoonMath.wrap(-0.25) - 0.75) < 1e-12)
        #expect(MoonMath.wrap(1) == 0)
        #expect(MoonMath.wrap(.nan) == 0 && MoonMath.wrap(.infinity) == 0)
        #expect(MoonMath.wrap(-1e-18) < 1)
    }

    @Test func terminatorRadiusIsRCosTwoPiPhase() {
        let r = 100.0
        #expect(abs(MoonMath.terminatorXRadius(radius: r, phase: 0) - r) < 1e-9)
        #expect(abs(MoonMath.terminatorXRadius(radius: r, phase: 0.25)) < 1e-9)
        #expect(abs(MoonMath.terminatorXRadius(radius: r, phase: 0.5) + r) < 1e-9)
        #expect(abs(MoonMath.terminatorXRadius(radius: r, phase: 0.75)) < 1e-9)
        for p in stride(from: 0.0, to: 1, by: 0.037) {
            #expect(abs(MoonMath.terminatorXRadius(radius: r, phase: p) - r * cos(2 * .pi * p)) < 1e-9)
        }
    }

    @Test func illuminationAndEarthshine() {
        #expect(MoonMath.illumination(0) == 0)
        #expect(abs(MoonMath.illumination(0.5) - 1) < 1e-12)
        #expect(abs(MoonMath.illumination(0.25) - 0.5) < 1e-12)
        #expect(abs(MoonMath.illumination(0.1) - MoonMath.illumination(0.9)) < 1e-12)
        #expect(MoonMath.earthshine(0) == 0.32)
        #expect(MoonMath.earthshine(0.25) < 1e-12 && MoonMath.earthshine(0.5) == 0)
        #expect(MoonMath.earthshine(0.05) > MoonMath.earthshine(0.15))
        #expect(MoonMath.isWaxing(0.2) && !MoonMath.isWaxing(0.6))
        #expect(abs(MoonMath.age(0.5) - 14.765294) < 1e-6)
    }

    @Test func litOutlineAreaMatchesIllumination() {
        let r = 80.0
        #expect(MoonMath.litOutline(phase: 0, radius: r).isEmpty)
        for p in [0.03, 0.125, 0.25, 0.4, 0.5, 0.6, 0.75, 0.875, 0.97] {
            let pts = MoonMath.litOutline(phase: p, radius: r, samples: 400)
            let expected = MoonMath.illumination(p) * .pi * r * r
            #expect(abs(MoonMath.area(of: pts) - expected) / (.pi * r * r) < 1e-3, "phase \(p)")
            #expect(pts.allSatisfy { $0.length <= r + 1e-9 })
        }
    }

    @Test func litSideIsRightWhenWaxingLeftWhenWaning() {
        let wax = MoonMath.litOutline(phase: 0.1, radius: 50), wane = MoonMath.litOutline(phase: 0.9, radius: 50)
        #expect(wax.allSatisfy { $0.x >= -1e-9 })
        #expect(wane.allSatisfy { $0.x <= 1e-9 })
        // Crescent thickness at the equator is r − rx.
        let maxX = wax.map(\.x).max()!, minX = wax.filter { abs($0.y) < 1e-6 }.map(\.x).min()!
        #expect(abs(maxX - 50) < 1e-9)
        #expect(abs(minX - MoonMath.terminatorXRadius(radius: 50, phase: 0.1)) < 1e-9)
        // Quarter: the terminator is the straight vertical diameter.
        let q = MoonMath.litOutline(phase: 0.25, radius: 50, samples: 16)
        #expect(q.suffix(15).allSatisfy { abs($0.x) < 1e-9 })
    }
}

@Suite("Named phases")
struct PhaseNameTests {
    @Test func eightPhasesEvenlySpaced() {
        #expect(MoonPhaseName.allCases.count == 8)
        #expect(MoonPhaseName.allCases.map(\.fraction) == (0..<8).map { Double($0) / 8 })
        #expect(MoonPhaseName.fullMoon.title == "Full Moon" && MoonPhaseName.waningCrescent.emoji == "🌘")
        #expect(Set(MoonPhaseName.allCases.map(\.title)).count == 8)
    }

    @Test func nearestWrapsAround() {
        #expect(MoonPhaseName.nearest(to: 0.97) == .newMoon)
        #expect(MoonPhaseName.nearest(to: -0.02) == .newMoon)
        #expect(MoonPhaseName.nearest(to: 0.3) == .firstQuarter)
        #expect(MoonPhaseName.nearest(to: 0.32) == .waxingGibbous)
        #expect(MoonPhaseName.nearest(to: 2.5) == .fullMoon)
        #expect(MoonPhaseName.nearest(to: .nan) == .newMoon)
    }

    @Test func snapTargetsTakeTheShortWay() {
        #expect(MoonPhaseName.snapTarget(near: 0.97) == 1)
        #expect(MoonPhaseName.snapTarget(near: -0.05) == 0)
        #expect(MoonPhaseName.snapTarget(near: 1.31) == 1.25)
        #expect(MoonPhaseName.unwrapped(.waningCrescent, near: 0.02) == -0.125)
        #expect(MoonPhaseName.unwrapped(.waxingCrescent, near: 0.95) == 1.125)
        #expect(MoonPhaseName.unwrapped(.fullMoon, near: 3.4) == 3.5)
    }

    @Test func readoutFormatting() {
        #expect(MoonFormatting.percentLit(0) == 0)
        #expect(MoonFormatting.percentLit(0.25) == 50)
        #expect(MoonFormatting.percentLit(0.5) == 100)
        #expect(MoonFormatting.percentLit(0.49) == 100)
        #expect(MoonFormatting.percentLit(0.125) == 15)
        #expect(MoonFormatting.age(0.5) == "Day 14 of 29.5")
        #expect(MoonFormatting.age(0) == "Day 0 of 29.5")
    }
}

@Suite("Scrub model")
struct ScrubModelTests {
    @Test func dragFollowsFingerOneToOne() {
        var m = MoonScrubModel(phase: 0)
        m.beginDrag()
        m.drag(translation: 90)
        #expect(abs(m.phase - 0.25) < 1e-12 && m.isDragging)
        m.drag(translation: -45)
        #expect(abs(m.phase - 0.875) < 1e-12)
        #expect(m.name == .waningCrescent)
        m.drag(translation: .nan)
        #expect(abs(m.phase - 0.875) < 1e-12)
    }

    @Test func releaseSnapsToNearestWithOvershoot() {
        var m = MoonScrubModel(phase: 0)
        m.beginDrag(); m.drag(translation: 100)        // 0.2778
        let target = m.endDrag(velocity: 0)
        #expect(target == 0.25)
        #expect(m.snapCount == 1)
        var below = false
        run(&m, 2) { if $0.unwrappedPhase < 0.25 - 1e-4 { below = true } }
        #expect(below, "the spring overshoots past the quarter")
        #expect(m.isSettled && abs(m.phase - 0.25) < 1e-4 && m.name == .firstQuarter)
    }

    @Test func flickProjectsAheadButIsLimited() {
        var m = MoonScrubModel(phase: 0)
        m.beginDrag(); m.drag(translation: 30)          // 0.083
        #expect(m.endDrag(velocity: 900) == 0.375)     // 0.083 + 0.3 → 0.383
        var n = MoonScrubModel(phase: 0)
        n.beginDrag(); n.drag(translation: 30)
        #expect(n.endDrag(velocity: 50_000) == 0.375)  // clamped to two steps past the release (0.333)
        var o = MoonScrubModel(phase: 0)
        o.beginDrag(); o.drag(translation: -10)
        #expect(o.endDrag(velocity: -800) == -0.25)
        #expect(MoonPhaseName.nearest(to: o.target) == .lastQuarter)
    }

    @Test func snapAcrossNewMoonDoesNotSpinTheLongWay() {
        var m = MoonScrubModel(phase: 0.9)
        m.beginDrag(); m.drag(translation: 25)          // 0.969
        #expect(m.endDrag(velocity: 0) == 1)
        var maxV = 0.0
        run(&m, 2) { maxV = max(maxV, abs($0.spring.velocity)) }
        #expect(maxV < 1, "a short hop, not a lap")
        #expect(m.name == .newMoon && m.phase < 1e-3 || m.phase > 1 - 1e-3)
    }

    @Test func selectAndAdvance() {
        var m = MoonScrubModel(phase: 0.95)
        m.select(.waxingCrescent)
        #expect(m.target == 1.125 && m.snapCount == 1)
        m.advance(1)
        #expect(m.target == 1.25 && m.snapCount == 2)
        m.advance(-3)
        #expect(m.target == 0.875)
        run(&m, 3)
        #expect(m.isSettled && m.name == .waningCrescent)
    }

    @Test func reduceMotionSnapsWithoutOvershoot() {
        var m = MoonScrubModel(phase: 0)
        m.reduceMotion = true
        m.beginDrag(); m.drag(translation: 100)
        #expect(m.endDrag(velocity: 2000) == 0.5)
        var over = false
        run(&m, 2) { if $0.unwrappedPhase > $0.target + 1e-6 { over = true } }
        #expect(!over)
        #expect(m.isSettled)
    }

    @Test func dragDoesNotStepAndUnwrappedValueStaysSmall() {
        var m = MoonScrubModel(phase: 0)
        m.beginDrag(); m.drag(translation: 45)
        run(&m, 0.5)
        #expect(abs(m.unwrappedPhase - 0.125) < 1e-12)
        m.endDrag(velocity: 0)
        for _ in 0..<80 { m.advance(1); run(&m, 1) }
        #expect(abs(m.unwrappedPhase) <= 9.2)
        #expect(m.name == .waxingCrescent)   // 0.125 plus ten whole laps
    }
}
