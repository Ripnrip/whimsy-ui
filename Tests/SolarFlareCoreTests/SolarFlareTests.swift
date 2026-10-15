import Testing
import Foundation
@testable import SolarFlareCore

private func run(_ m: inout SolarFlareModel, seconds: Double, fps: Double = 60) -> [Double] {
    (0..<Int(seconds * fps)).map { _ in m.step(dt: 1 / fps); return m.scale }
}

@Suite("Spring response")
struct SpringResponseTests {
    @Test func startsAtZeroOvershootsThenSettlesAtOne() {
        #expect(springResponse(0, omega: 22, zeta: 0.55) == 0)
        #expect(springResponse(-1, omega: 22, zeta: 0.55) == 0)
        let samples = stride(from: 0.0, through: 1.5, by: 0.002).map { springResponse($0, omega: 22, zeta: 0.55) }
        let peak = samples.max()!
        // Underdamped overshoot exp(−ζπ/√(1−ζ²)) ≈ 12.6% at ζ 0.55.
        #expect(abs(peak - (1 + exp(-0.55 * .pi / (1 - 0.55 * 0.55).squareRoot()))) < 1e-3)
        #expect(abs(samples.last! - 1) < 1e-4)
    }
}

@Suite("Ribbons")
struct RibbonTests {
    let ribbon = FlareRibbon(angle: 0.3, delay: 0.05, length: 1, width: 0.1, swirl: 0.4, innerRadius: 0.72)

    @Test func hiddenBeforeLaunchAndAfterLifetime() {
        #expect(ribbon.state(at: 0.04) == nil)
        #expect(ribbon.state(at: 0.05 + 0.62) == nil)
        #expect(ribbon.state(at: 0.2) != nil)
    }

    @Test func extendsThenDetachesAndFades() {
        let early = ribbon.state(at: 0.05 + 0.04)!, mid = ribbon.state(at: 0.05 + 0.2)!, late = ribbon.state(at: 0.05 + 0.5)!
        #expect(early.tail == 0 && early.head > 0.1)           // tail hasn't left yet
        #expect(mid.tail > 0 && mid.head > 0.9)                // detached, near full length
        #expect(late.head - late.tail < mid.head - mid.tail)   // shrinking away
        #expect(early.opacity > mid.opacity && mid.opacity > late.opacity && late.opacity > 0)
        #expect(early.opacity <= 1)
    }

    @Test func centrelineIsRadialWithSwirl() {
        let start = ribbon.centerline(0), tip = ribbon.centerline(1)
        #expect(abs(start.length - 0.72) < 1e-12 && abs(tip.length - 1.72) < 1e-12)
        #expect(abs(atan2(start.y, start.x) - 0.3) < 1e-12)
        #expect(abs(atan2(tip.y, tip.x) - 0.7) < 1e-12)        // bent by the swirl at the tip
        // Monotone outward.
        let radii = stride(from: 0.0, through: 1.0, by: 0.05).map { ribbon.centerline($0).length }
        #expect(zip(radii, radii.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func taperIsZeroAtBothEndsAndPeaksNearTheBase() {
        #expect(FlareRibbon.taper(0) == 0 && FlareRibbon.taper(1) == 0)
        let us = stride(from: 0.0, through: 1.0, by: 0.01)
        let peakU = us.max { FlareRibbon.taper($0) < FlareRibbon.taper($1) }!
        #expect(peakU > 0.1 && peakU < 0.3)
        #expect(us.allSatisfy { FlareRibbon.taper($0) <= 1 && FlareRibbon.taper($0) >= 0 })
    }

    @Test func outlineIsClosedTaperedAndHugsTheCentreline() {
        let s = RibbonState(tail: 0.2, head: 0.9, opacity: 1)
        let pts = ribbon.outline(s, samples: 16)
        #expect(pts.count == 34)
        // Pointed ends: the first/last left and right points coincide with the centreline.
        #expect(pts[0].distance(to: ribbon.centerline(0.2)) < 1e-9)
        #expect(pts[16].distance(to: ribbon.centerline(0.9)) < 1e-9)
        // Never wider than the max half-width.
        for i in 0...16 {
            let d = 0.2 + 0.7 * Double(i) / 16
            #expect(pts[i].distance(to: ribbon.centerline(d)) <= 0.1 + 1e-9)
        }
        #expect(ribbon.outline(RibbonState(tail: 0.5, head: 0.5, opacity: 1)).isEmpty)
    }
}

@Suite("Like model")
struct SolarFlareModelTests {
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func burstHasSevenToNineEvenlySpreadRibbons(seed: UInt64) {
        var m = SolarFlareModel(seed: seed)
        m.setLiked(true)
        let n = m.ribbons.count
        #expect((7...9).contains(n))
        let sorted = m.ribbons.map { $0.angle }.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        let spacing = 2 * Double.pi / Double(n)
        #expect(gaps.allSatisfy { $0 > spacing * 0.5 && $0 < spacing * 1.5 })
        // One shared swirl direction, staggered launches inside the window.
        #expect(Set(m.ribbons.map { $0.swirl > 0 }).count == 1)
        #expect(m.ribbons.allSatisfy { $0.delay >= 0 && $0.delay <= 0.12 + 1e-12 })
        #expect(Set(m.ribbons.map(\.delay)).count == n)
        #expect(m.ribbons.allSatisfy { (0.75...1.25).contains($0.length) && (0.10...0.16).contains($0.width) })
    }

    @Test func ribbonCountsCoverTheWholeRange() {
        var counts = Set<Int>()
        for seed in UInt64(0)..<60 {
            var m = SolarFlareModel(seed: seed)
            m.setLiked(true)
            counts.insert(m.ribbons.count)
        }
        #expect(counts == [7, 8, 9])
    }

    @Test func likePulsesToAboutOnePointTwoFiveAndBack() {
        var m = SolarFlareModel()
        m.setLiked(true)
        let trace = run(&m, seconds: 1.2)
        let peak = trace.max()!
        #expect(peak > 1.2 && peak < 1.32)
        #expect(trace.firstIndex(of: peak)! < 12)               // peaks within 0.2 s
        #expect(abs(m.scale - 1) < 1e-3 && m.isSettled && m.isLiked)
    }

    @Test func ribbonsLaunchStaggeredThenAllFade() {
        var m = SolarFlareModel(seed: 9)
        m.setLiked(true)
        #expect(m.visibleRibbons.count <= 1)                     // only the first can be up at t = 0
        _ = run(&m, seconds: 0.15)
        #expect(m.visibleRibbons.count == m.ribbons.count)
        _ = run(&m, seconds: 1)
        #expect(m.ribbons.isEmpty && m.visibleRibbons.isEmpty)
    }

    @Test func unlikeIsAQuickShrinkWithNoFlare() {
        var m = SolarFlareModel(isLiked: true)
        m.setLiked(false)
        #expect(m.ribbons.isEmpty)
        let trace = run(&m, seconds: 0.8)
        #expect(trace.min()! < 0.88 && trace.min()! > 0.7)
        #expect(trace.max()! < 1.08)                              // no big rebound
        #expect(m.isSettled && !m.isLiked && m.burstCount == 0)
    }

    @Test func unlikeMidBurstKillsTheFlare() {
        var m = SolarFlareModel()
        m.setLiked(true); _ = run(&m, seconds: 0.1)
        #expect(!m.visibleRibbons.isEmpty)
        m.toggle()
        #expect(m.ribbons.isEmpty && !m.isLiked)
    }

    @Test func eachLikeIsADifferentBurstButTheSequenceIsSeeded() {
        var a = SolarFlareModel(seed: 3), b = SolarFlareModel(seed: 3)
        a.setLiked(true); b.setLiked(true)
        #expect(a.ribbons == b.ribbons)
        let first = a.ribbons
        a.setLiked(false); a.setLiked(true)
        #expect(a.ribbons != first && a.burstCount == 2)
    }

    @Test func nonAnimatedChangesAreInstant() {
        var m = SolarFlareModel()
        m.setLiked(true, animated: false)
        #expect(m.isLiked && m.ribbons.isEmpty && m.isSettled && m.scale == 1)
        m.setLiked(true)                                          // no-op: already liked
        #expect(m.ribbons.isEmpty)
    }

    @Test func deterministicAndSafeSteps() {
        var a = SolarFlareModel(seed: 12), b = SolarFlareModel(seed: 12)
        a.setLiked(true); b.setLiked(true)
        #expect(run(&a, seconds: 0.5) == run(&b, seconds: 0.5))
        let before = a
        a.step(dt: 0); a.step(dt: -1); a.step(dt: .nan)
        #expect(a == before)
        a.step(dt: 99)
        #expect(abs(a.time - before.time - 0.1) < 1e-9)
    }

    @Test func pulseIsFrameRateIndependentEnough() {
        var a = SolarFlareModel(), b = SolarFlareModel()
        a.setLiked(true); b.setLiked(true)
        let ta = run(&a, seconds: 0.5, fps: 60), tb = run(&b, seconds: 0.5, fps: 120)
        #expect(abs(ta.max()! - tb.max()!) < 0.01)
    }
}
