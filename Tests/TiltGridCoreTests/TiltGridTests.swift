import Foundation
import Testing
@testable import TiltGridCore

@Suite("Kinetic intro")
struct IntroTests {
    let intro = KineticIntro()

    @Test func phrasesSplitIntoWords() {
        #expect(intro.phrases == [["WHIMSY", "STUDIO"], ["PHOTO", "ALBUM", "2026"], ["2026", "SHOWCASE", "APERTURE"]])
        #expect(intro.totalCuts == 8)
        #expect(KineticIntro(phrases: ["  A  B ", ""]).phrases == [["A", "B"]])
    }

    @Test func scheduleAddsUp() {
        #expect(intro.start(ofPhrase: 0) == 0.25)
        #expect(abs(intro.start(ofPhrase: 1) - (0.25 + 0.28 + 0.5)) < 1e-12)
        #expect(abs(intro.start(ofPhrase: 2) - (1.03 + 0.42 + 0.5)) < 1e-12)
        #expect(abs(intro.outroStart - (1.95 + 0.92)) < 1e-12)
        #expect(abs(intro.duration - (2.87 + 0.45)) < 1e-12)
    }

    @Test func wordsCutInOneAtATime() {
        #expect(intro.frame(at: 0.1).phrase == nil && intro.frame(at: 0.1).cuts == 0)
        let a = intro.frame(at: 0.26)
        #expect(a.phrase == 0 && a.words == 1 && a.cuts == 1 && abs(a.sinceCut - 0.01) < 1e-9)
        #expect(intro.frame(at: 0.40).words == 2)
        #expect(intro.frame(at: 1.0).words == 2 && intro.frame(at: 1.0).phrase == 0, "holding")
        let b = intro.frame(at: 1.04)
        #expect(b.phrase == 1 && b.words == 1 && b.cuts == 3, "hard cut to the next phrase")
        #expect(intro.frame(at: 2.3).phrase == 2 && intro.frame(at: 2.3).cuts == 8)
        var last = 0
        for i in 0...400 { let c = intro.frame(at: Double(i) / 100).cuts; #expect(c >= last); last = c }
        #expect(last == 8)
    }

    @Test func vanishesThenFinishes() {
        let mid = intro.frame(at: intro.outroStart + 0.2)
        #expect(mid.outro > 0.4 && mid.outro < 0.5 && mid.phrase == 2 && !mid.isFinished)
        #expect(abs(mid.reveal - 0.2) < 1e-9)
        let end = intro.frame(at: 10)
        #expect(end.isFinished && end.phrase == nil && end.outro == 1)
        #expect(intro.frame(at: 1).reveal < 0)
        #expect(intro.frame(at: .nan).cuts == 0)
    }

    @Test func slamAndVanishCurves() {
        #expect(abs(KineticIntro.slamScale(sinceCut: 0) - 1.22) < 1e-12)
        #expect(KineticIntro.slamScale(sinceCut: 0.09) == 1 && KineticIntro.slamScale(sinceCut: 1) == 1)
        #expect(KineticIntro.slamScale(sinceCut: 0.03) > KineticIntro.slamScale(sinceCut: 0.06))
        #expect(KineticIntro.slamScale(sinceCut: -1) == 1)
        let v0 = KineticIntro.vanish(0), v1 = KineticIntro.vanish(1)
        #expect(v0.opacity == 1 && v0.scale == 1 && v0.rise == 0)
        #expect(v1.opacity == 0 && abs(v1.scale - 0.88) < 1e-12 && v1.rise == -60)
    }
}

@Suite("Masonry grid")
struct MasonryTests {
    let g = MasonryGrid()

    @Test func cardsFillShortestColumnsWithoutOverlap() {
        #expect(g.cards.count == 18)
        let cw = (473.0 - 40) / 3
        for c in g.cards {
            #expect(abs(c.width - cw) < 1e-9)
            #expect(c.height >= (cw * 1.0).rounded() - 1 && c.height <= (cw * 1.55).rounded() + 1)
            #expect(c.x >= 10 - 1e-9 && c.x + c.width <= 473 - 10 + 1e-9)
        }
        for a in g.cards { for b in g.cards where a.index < b.index {
            let overlap = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
            #expect(!overlap, "\(a.index) vs \(b.index)")
        } }
        // Columns stay balanced: no column ends more than one tall card below another.
        let ends = (0..<3).map { col in g.cards.filter { $0.column == col }.map { $0.y + $0.height }.max() ?? 0 }
        #expect(ends.max()! - ends.min()! <= cw * 1.55 + 10)
        #expect(abs(g.height - (ends.max()! + 10)) < 1e-9)
    }

    @Test func eachColumnStacksWithSpacing() {
        for col in 0..<3 {
            let cs = g.cards.filter { $0.column == col }.sorted { $0.y < $1.y }
            #expect(cs.first?.y == 10)
            for (a, b) in zip(cs, cs.dropFirst()) { #expect(abs(b.y - (a.y + a.height + 10)) < 1e-9) }
        }
    }

    @Test func seededAndDeterministic() {
        #expect(MasonryGrid() == MasonryGrid())
        #expect(MasonryGrid(seed: 1) != MasonryGrid(seed: 2))
        for c in g.cards {
            #expect(c.depth >= 0 && c.depth <= 1)
            #expect((0...4).contains(c.portrait.skin) && (0...3).contains(c.portrait.hairStyle))
            #expect(abs(c.portrait.lean) <= 0.15)
            #expect(c.portrait.backgroundBottom >= 0 && c.portrait.backgroundBottom < 1)
        }
        #expect(Set(g.cards.map(\.portrait.hairStyle)).count >= 3, "variety")
        #expect(MasonryGrid(count: 0).cards.isEmpty && MasonryGrid(count: 0).height == 10)
    }

    @Test func revealRipplesOutFromTheOrigin() {
        let o = Vec2(g.width / 2, g.height / 2)
        let sorted = g.cards.sorted { g.revealDelay(of: $0, from: o) < g.revealDelay(of: $1, from: o) }
        #expect(sorted.first!.center.distance(to: o) <= sorted.last!.center.distance(to: o))
        #expect(g.revealDelay(of: g.cards[0], from: g.cards[0].center) == 0)
    }
}

@Suite("Plane tilt")
struct TiltTests {
    @Test func normalisesToTheContainer() {
        let s = Vec2(393, 852)
        #expect(PlaneTilt.normalized(Vec2(196.5, 426), in: s) == .zero)
        #expect(PlaneTilt.normalized(Vec2(0, 0), in: s) == Vec2(-1, -1))
        #expect(PlaneTilt.normalized(Vec2(1000, 852), in: s) == Vec2(1, 1))
        #expect(PlaneTilt.normalized(Vec2(.nan, 3), in: s) == .zero)
        #expect(PlaneTilt.normalized(Vec2(1, 1), in: .zero) == .zero)
    }

    @Test func tiltsAndPansAwayFromTheFinger() {
        var p = PlaneTilt()
        p.setInput(Vec2(1, -1))   // top-right corner
        #expect(p.tiltTarget == Vec2(16, 14), "right and top edges recede")
        #expect(p.panTarget == Vec2(-30, 46), "the plane slides away: left and down")
        p.setInput(Vec2(-0.5, 0.5))
        #expect(p.tiltTarget == Vec2(-8, -7) && p.panTarget == Vec2(15, -23))
        p.setInput(Vec2(4, -9))
        #expect(p.input == Vec2(1, -1))
        p.setInput(Vec2(.nan, 0))
        #expect(p.input == Vec2(1, -1))
        p.setInput(nil)
        #expect(p.tiltTarget == .zero && p.panTarget == .zero)
    }

    @Test func springsOvershootThenSettle() {
        var p = PlaneTilt()
        p.setInput(Vec2(1, 0))
        var peak = 0.0
        for _ in 0..<180 { p.step(1.0 / 60); peak = max(peak, p.tilt.value.x) }
        #expect(peak > 16.5, "a little overshoot")
        #expect(abs(p.tilt.value.x - 16) < 0.05 && abs(p.pan.value.x + 30) < 0.1)
        #expect(p.isSettled)
        p.setInput(nil)
        for _ in 0..<240 { p.step(1.0 / 60) }
        #expect(p.isSettled && p.tilt.value.length < 0.02)
    }

    @Test func parallaxScalesWithDepthAndPan() {
        var p = PlaneTilt()
        #expect(p.parallax(depth: 1) == .zero)
        p.setInput(Vec2(1, 1))
        for _ in 0..<300 { p.step(1.0 / 60) }
        let near = p.parallax(depth: 1), mid = p.parallax(depth: 0.5), flat = p.parallax(depth: 0)
        #expect(abs(near.x + 18) < 0.1 && abs(near.y + 18) < 0.1)
        #expect(abs(mid.x - near.x / 2) < 1e-9)
        #expect(flat == .zero)
        #expect(p.parallax(depth: 7) == near && p.parallax(depth: .nan) == .zero)
    }

    @Test func reduceMotionIsGentleAndDoesNotOvershoot() {
        var p = PlaneTilt()
        p.reduceMotion = true
        p.setInput(Vec2(1, 0))
        var peak = 0.0
        for _ in 0..<300 { p.step(1.0 / 60); peak = max(peak, p.tilt.value.x) }
        #expect(abs(p.tiltTarget.x - 5.6) < 1e-9)
        #expect(peak <= 5.6 + 1e-6)
    }

    @Test func deviceMotionMapsLikeAFinger() {
        #expect(MotionTilt.normalized(pitch: 0.6, roll: 0) == .zero)
        #expect(MotionTilt.normalized(pitch: 0.6, roll: 0.35) == Vec2(1, 0))
        #expect(MotionTilt.normalized(pitch: 2, roll: -2) == Vec2(-1, 1))
        #expect(abs(MotionTilt.normalized(pitch: 0.425, roll: 0).y + 0.5) < 1e-9)
        #expect(MotionTilt.normalized(pitch: .nan, roll: 0) == .zero)
    }
}
