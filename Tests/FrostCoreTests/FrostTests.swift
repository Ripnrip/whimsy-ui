import Testing
import Foundation
@testable import FrostCore

private let card = Vec2(320, 200)
private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
private func angleBetween(_ a: Vec2, _ b: Vec2) -> Double { acos(max(-1, min(1, a.normalized.dot(b.normalized)))) }

@Suite struct CrystalPatternTests {
    @Test func patternIsSeededAndDeterministic() {
        let a = CrystalPattern(size: card, seed: 7), b = CrystalPattern(size: card, seed: 7)
        #expect(a == b)
        #expect(a.branches != CrystalPattern(size: card, seed: 8).branches)
        // 22 stems around a 1040 pt perimeter (1040 / 48 ≈ 21.7), each with 3 → 2 → 2 descendants: 22 × (1 + 3 + 6 + 12).
        #expect(a.branches.filter { $0.generation == 0 }.count == 22)
        #expect(a.branches.count == 22 * 22)
        #expect(a.maxGeneration == 3)
    }

    @Test func stemsStartOnTheEdgesAndPointInward() {
        let p = CrystalPattern(size: card)
        let stems = p.branches.filter { $0.generation == 0 }
        for s in stems {
            let onEdge = near(s.start.x, 0) || near(s.start.x, card.x) || near(s.start.y, 0) || near(s.start.y, card.y)
            #expect(onEdge)
            let inward: Vec2 = near(s.start.y, 0) ? Vec2(0, 1) : near(s.start.x, card.x) ? Vec2(-1, 0)
                : near(s.start.y, card.y) ? Vec2(0, -1) : Vec2(1, 0)
            #expect(angleBetween(s.direction, inward) <= 0.35 + 1e-9)
            #expect(s.length >= 0.22 * 200 - 1e-9 && s.length <= 0.34 * 200 + 1e-9)
            #expect(s.parent == nil)
        }
        // Spread all the way round: every side has stems.
        #expect(stems.contains { near($0.start.y, 0) } && stems.contains { near($0.start.y, card.y) })
        #expect(stems.contains { near($0.start.x, 0) } && stems.contains { near($0.start.x, card.x) })
    }

    @Test func childrenBranchAtSixtyDegreesAndShrink() throws {
        let p = CrystalPattern(size: card)
        var left = 0, right = 0
        for b in p.branches where b.generation > 0 {
            let parent = p.branches[try #require(b.parent)]
            #expect(b.generation == parent.generation + 1)
            let off = angleBetween(b.direction, parent.direction)
            #expect(abs(off - .pi / 3) <= 0.1 + 1e-9)
            if parent.direction.cross(b.direction) > 0 { right += 1 } else { left += 1 }
            #expect(b.length < parent.length && b.length >= parent.length * 0.42 - 1e-9)
            #expect(near(b.width, parent.width * 0.62))
            // It sprouts from a point on the parent, between 28 % and 88 % along it.
            let t = (b.start - parent.start).dot(parent.direction) / parent.length
            #expect(t >= 0.28 - 1e-9 && t <= 0.88 + 1e-9)
            #expect((b.start - parent.start).cross(parent.direction).magnitude < 1e-9)
        }
        // Alternating sides: balanced to within one per family.
        #expect(abs(left - right) <= p.branches.filter { $0.generation < 3 }.count)
        #expect(left > 100 && right > 100)
    }

    @Test func childrenSpawnWhenTheParentTipPassesAndAllFinishByTheEnd() throws {
        let p = CrystalPattern(size: card)
        for b in p.branches {
            #expect(b.birth >= 0 && b.span > 0)
            #expect(b.fullAt <= 0.97 + 1e-9)
            if let pi = b.parent {
                let parent = p.branches[pi]
                // At the child's birth, the parent's tip is exactly at the sprout point.
                #expect(parent.tip(at: b.birth).distance(to: b.start) < 1e-6)
                #expect(b.birth > parent.birth)
            }
        }
        #expect(near(p.branches.map(\.fullAt).max() ?? 0, 0.97))
        // Growth is the same speed everywhere: span ∝ length.
        let ratios = p.branches.map { $0.span / $0.length }
        #expect((ratios.max() ?? 0) - (ratios.min() ?? 1) < 1e-12)
        #expect(p.spawnOrder.count == p.branches.count)
        #expect(zip(p.spawnOrder, p.spawnOrder.dropFirst()).allSatisfy { p.branches[$0].birth <= p.branches[$1].birth })
    }

    @Test func growthIsMonotoneAndClamped() {
        let b = CrystalBranch(start: .zero, angle: 0, length: 40, width: 2, generation: 0, parent: nil, birth: 0.2, span: 0.4)
        #expect(b.growth(at: 0.1) == 0 && b.growth(at: 0.2) == 0)
        #expect(near(b.growth(at: 0.4), 0.5, 1e-12) && near(b.growth(at: 0.6), 1, 1e-12) && b.growth(at: 0.7) == 1 && b.growth(at: 1) == 1)
        #expect(near(b.tip(at: 0.4).x, 20, 1e-9))
        let p = CrystalPattern(size: card)
        var last = -1
        for k in 0...20 {
            let n = p.spawnedCount(at: Double(k) / 20)
            #expect(n >= last)
            last = n
        }
        #expect(p.spawnedCount(at: 0) == 0 && p.spawnedCount(at: 1) == p.branches.count)
    }
}

@Suite struct FrostModelTests {
    private func run(_ m: inout FrostModel, seconds: Double, fps: Double = 60) -> [FrostEvent] {
        var all: [FrostEvent] = []
        for _ in 0..<Int((seconds * fps).rounded()) { all += m.step(1 / fps) }
        return all
    }

    @Test func holdingGrowsAndEmitsEachSpawnOnceInOrder() {
        var m = FrostModel(size: card)
        #expect(m.isIdle)
        m.press()
        _ = run(&m, seconds: 1.5)
        #expect(near(m.progress, 0.5, 1e-9))
        let rest = run(&m, seconds: 2)
        #expect(m.progress == 1)
        var spawned: [Int] = []
        var m2 = FrostModel(size: card)
        m2.press()
        for e in run(&m2, seconds: 3.5) { if case let .spawn(i) = e { spawned.append(i) } }
        #expect(spawned == m2.pattern.spawnOrder)            // every branch, once, in birth order
        #expect(m2.spawns == m2.pattern.branches.count)
        #expect(!rest.contains { if case .melted = $0 { true } else { false } })
    }

    @Test func hapticTicksAreThrottled() {
        var m = FrostModel(size: card)
        m.press()
        _ = run(&m, seconds: 3.2)
        #expect(m.ticks > 20)
        #expect(m.ticks <= Int(3.0 / 0.07) + 1)
        #expect(m.ticks < m.spawns)
    }

    @Test func releaseMeltsBackWithBlurAndDroplets() {
        var m = FrostModel(size: card)
        m.press(); _ = run(&m, seconds: 3.1)
        m.release()
        let melt1 = run(&m, seconds: 0.3)
        #expect(near(m.progress, 1 - 0.3 / 1.3, 1e-9))
        #expect(m.isMelting && m.melt == 1 && m.blurRadius == 3.5)
        #expect(melt1.allSatisfy { if case .melted = $0 { true } else { false } })
        #expect(!m.droplets.isEmpty)
        let events = melt1 + run(&m, seconds: 1.1)
        #expect(m.progress == 0)
        // Youngest first: melt order is the reverse of spawn order.
        let melted = events.compactMap { if case let .melted(i) = $0 { i } else { nil } }
        #expect(melted == Array(m.pattern.spawnOrder.reversed()))
        #expect(m.droplets.count <= 36)
        _ = run(&m, seconds: 2)
        #expect(m.isIdle && m.droplets.isEmpty && m.melt == 0)
    }

    @Test func dropletsSlideDownAndFade() {
        var d = Droplet(position: Vec2(10, 20), radius: 2, life: 1.2)
        #expect(d.opacity == 0)
        d.step(0.04)
        #expect(d.opacity > 0.4 && d.opacity < 0.6)
        var lastY = d.position.y
        for _ in 0..<30 { d.step(1.0 / 60); #expect(d.position.y > lastY); lastY = d.position.y }
        #expect(d.position.x == 10)
        #expect(d.velocity < Droplet.terminalVelocity && d.velocity > 0.9 * Droplet.terminalVelocity)
        while !d.isFinished { d.step(1.0 / 60) }
        #expect(d.opacity == 0)
        #expect(near(d.age, 1.2, 1 / 60 + 1e-9))
    }

    @Test func repressingMidMeltRegrowsAndRespawns() {
        var m = FrostModel(size: card)
        m.press(); _ = run(&m, seconds: 1.2)
        let peak = m.pattern.spawnedCount(at: m.progress)
        m.release(); let melted = run(&m, seconds: 0.4).count
        m.press()
        let again = run(&m, seconds: 0.52)
        #expect(m.progress > 0.4 - 0.4 / 1.3)
        #expect(m.pattern.spawnedCount(at: m.progress) == peak - melted + again.count)
        #expect(m.spawns == peak + again.count)
    }

    @Test func frameRateIndependent() {
        var a = FrostModel(size: card), b = FrostModel(size: card)
        a.press(); b.press()
        let ea = run(&a, seconds: 2, fps: 120), eb = run(&b, seconds: 2, fps: 30)
        #expect(near(a.progress, b.progress, 1e-9))
        #expect(ea.count == eb.count)
        a.release(); b.release()
        _ = run(&a, seconds: 0.6, fps: 120); _ = run(&b, seconds: 0.6, fps: 30)
        #expect(near(a.progress, b.progress, 1e-9) && a.droplets.count == b.droplets.count)
    }

    @Test func reduceMotionAndResize() {
        var cfg = FrostModel.Config(); cfg.reduceMotion = true
        var m = FrostModel(size: card, config: cfg)
        m.press(); _ = run(&m, seconds: 3.1)
        m.release(); _ = run(&m, seconds: 0.5)
        #expect(m.droplets.isEmpty && m.blurRadius == 0)
        var r = FrostModel(size: card)
        r.resize(to: Vec2(300, 180))
        #expect(r.pattern.size == Vec2(300, 180))
        r.press(); _ = r.step(0.1)
        r.resize(to: card)
        #expect(r.pattern.size == Vec2(300, 180))           // not mid-frost
        let big = r.step(5)                                 // a hitch is clamped to one 0.1 s frame
        #expect(near(r.progress, 0.2 / 3, 1e-9) && !big.isEmpty)
    }
}
