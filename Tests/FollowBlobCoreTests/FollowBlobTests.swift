import Foundation
import Testing
@testable import FollowBlobCore

private func run(_ m: inout FollowBlobModel, _ seconds: Double, _ each: (FollowBlobModel) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * 60).rounded()) { m.step(1.0 / 60); each(m) }
}

@Suite("Chase spring")
struct ChaseTests {
    @Test func followerLagsBehindTheLeader() {
        var c = ChaseSpring(at: .zero)
        let target = Vec2(300, 0)
        for _ in 0..<24 { c.substep(toward: target, h: 1.0 / 240) }          // 0.1 s
        #expect(c.leader.value.x > c.position.x)
        #expect(c.position.x < 0.25 * 300)
        for _ in 0..<(240 * 6) { c.substep(toward: target, h: 1.0 / 240) }
        #expect(c.isSettled(at: target))
    }

    @Test func landsWithOnlyAGentleOvershoot() {
        var c = ChaseSpring(at: .zero)
        var peak = 0.0
        for _ in 0..<(240 * 4) { c.substep(toward: Vec2(100, 0), h: 1.0 / 240); peak = max(peak, c.position.x) }
        #expect(peak < 115)            // a soft landing, not a bounce
        #expect(abs(c.position.x - 100) < 0.5)
    }
}

@Suite("Blob morph")
struct MorphTests {
    let morph = BlobMorph()

    @Test func stretchGrowsWithSpeedAndCaps() {
        #expect(morph.stretch(for: .zero) == 0)
        #expect(abs(morph.stretch(for: Vec2(700, 0)) - 0.225) < 1e-12)
        #expect(morph.stretch(for: Vec2(1e5, 0)) == 0.45)
        #expect(morph.stretch(for: Vec2(.nan, 0)) == 0)
        #expect(morph.lobeGain(for: .zero) == 0.6 && morph.lobeGain(for: Vec2(0, 2_000)) == 1.4)
    }

    @Test func squashAndStretchPreservesArea() {
        let r = morph.baseRadius
        for v in [Vec2.zero, Vec2(500, 0), Vec2(-900, 600), Vec2(0, 5_000)] {
            let p = morph.outline(time: 0, velocity: v, samples: 360, wobble: false)
            #expect(abs(BlobMorph.area(of: p) / (.pi * r * r) - 1) < 1e-3)
        }
    }

    @Test func stretchPointsAlongTheVelocity() {
        let v = Vec2(-600, 800)
        let p = morph.outline(time: 0, velocity: v, samples: 360, wobble: false)
        let far = p.max { $0.length < $1.length }!
        #expect(abs(abs(far.normalized.dot(v.normalized)) - 1) < 1e-3)
        #expect(abs(far.length - morph.baseRadius * (1 + morph.stretch(for: v))) < 0.05)   // 1° sampling
    }

    @Test func lobesWobbleWithinTheirAmplitude() {
        let total = BlobMorph.defaultLobes.map(\.amplitude).reduce(0, +)
        for t in stride(from: 0.0, through: 10, by: 0.7) {
            for p in morph.outline(time: t, velocity: .zero, samples: 64) {
                let k = p.length / morph.baseRadius
                #expect(k >= 1 - 0.6 * total - 1e-9 && k <= 1 + 0.6 * total + 1e-9)
            }
        }
        let a = morph.outline(time: 0, velocity: .zero), b = morph.outline(time: 1, velocity: .zero)
        #expect(a != b)                                    // it moves over time
        #expect(a.count == 96 && morph.outline(time: 0, velocity: .zero, samples: 3).count == 8)
    }
}

@Suite("Mesh, palettes and the model")
struct BlobModelTests {
    @Test func meshPinsCornersAndKeepsEdgesOnTheirEdges() {
        for t in stride(from: 0.0, through: 20, by: 1.3) {
            let p = MeshField.points(time: t, velocity: Vec2(3_000, -3_000))
            #expect(p.count == 9)
            #expect(p[0] == Vec2(0, 0) && p[2] == Vec2(1, 0) && p[6] == Vec2(0, 1) && p[8] == Vec2(1, 1))
            #expect(p[1].y == 0 && p[7].y == 1 && p[3].x == 0 && p[5].x == 1)
            for e in [p[1].x, p[7].x, p[3].y, p[5].y] { #expect(e >= 0.3 && e <= 0.7) }
            #expect(p[4].x >= 0.15 && p[4].x <= 0.85 && p[4].y >= 0.15 && p[4].y <= 0.85)
        }
    }

    @Test func palettesHaveNineColoursAndCrossfade() {
        #expect(BlobPalette.all.allSatisfy { $0.colors.count == 9 })
        var m = FollowBlobModel(size: Vec2(393, 852))
        #expect(m.meshColors == BlobPalette.neon.colors)
        m.setPalette(2)
        #expect(m.meshColors == BlobPalette.neon.colors)       // the fade starts from what's on screen
        run(&m, 0.3)
        let mid = m.meshColors[0]
        #expect(mid != BlobPalette.neon.colors[0] && mid != BlobPalette.lagoon.colors[0])
        run(&m, 0.4)
        #expect(m.meshColors == BlobPalette.lagoon.colors)
        m.setPalette(99)
        #expect(m.palette == 3)
        m.setPalette(3)                                        // same palette: no restart
        #expect(m.previousPalette == 2)
    }

    @Test func idlesOnAnOrbitAroundHome() {
        var m = FollowBlobModel(size: Vec2(393, 852))
        var minX = 1e9, maxX = -1e9
        run(&m, 30) { m in minX = min(minX, m.center.x); maxX = max(maxX, m.center.x) }
        #expect(maxX - minX > 40)                               // it drifts...
        #expect(minX > 0.68 * 393 - 0.12 * 393 - 10 && maxX < 0.68 * 393 + 0.12 * 393 + 10)  // ...near home
        #expect(m.finger == nil && m.target == m.orbit(at: m.time))
    }

    @Test func followsTheFingerAndMorphsWhileMoving() {
        var m = FollowBlobModel(size: Vec2(393, 852))
        m.setFinger(Vec2(60, 700))
        var maxStretch = 0.0
        run(&m, 0.6) { m in maxStretch = max(maxStretch, m.stretch) }
        #expect(maxStretch > 0.2)
        run(&m, 4)
        #expect(m.center.distance(to: Vec2(60, 700)) < 1)
        #expect(m.stretch < 0.01)
        m.setFinger(Vec2(.nan, 3))
        #expect(m.finger == Vec2(60, 700))
    }

    @Test func reduceMotionHoldsStillAndNeverOvershoots() {
        var m = FollowBlobModel(size: Vec2(393, 852))
        m.reduceMotion = true
        let home = m.center
        run(&m, 3)
        #expect(m.center.distance(to: home) < 1e-6)
        m.setFinger(Vec2(60, home.y))
        run(&m, 3) { m in #expect(m.center.x >= 60 - 1e-6) }
        #expect(m.stretch == 0 && m.outline(samples: 32).allSatisfy { abs($0.length - 130) < 1e-9 })
        m.setPalette(1)
        #expect(m.meshColors == BlobPalette.sunset.colors)      // instant swap
    }

    @Test func resizingKeepsTheBlobInProportion() {
        var m = FollowBlobModel(size: Vec2(400, 800))
        let before = m.center
        m.setSize(Vec2(800, 400))
        #expect(abs(m.center.x - before.x * 2) < 1e-9 && abs(m.center.y - before.y / 2) < 1e-9)
        m.setSize(Vec2(0, 10)); m.setSize(Vec2(.nan, 10))
        #expect(m.size == Vec2(800, 400))
    }
}
