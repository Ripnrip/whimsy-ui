import Testing
import Foundation
@testable import PaintCore

private let card = Vec2(320, 420)
private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

/// A straight stroke from a to b sampled at 60 Hz over `duration` seconds starting at t0.
private func paint(_ m: inout PaintModel, from a: Vec2, to b: Vec2, t0: Double, duration: Double) -> [PaintEvent] {
    var out: [PaintEvent] = []
    let n = max(Int((duration * 60).rounded()), 1)
    for i in 0...n {
        let t = t0 + Double(i) / 60
        m.dragChanged(to: a + (b - a) * (Double(i) / Double(n)), at: t)
        out += m.advance(to: t)
    }
    m.dragEnded(at: t0 + Double(n) / 60)
    out += m.advance(to: t0 + Double(n) / 60)
    return out
}

@Suite struct CaptureTests {
    @Test func widthComesFromVelocity() {
        #expect(StrokeWidth.target(speed: 0) == StrokeWidth.maxWidth)
        #expect(StrokeWidth.target(speed: 5000) == StrokeWidth.minWidth)
        var last = Double.infinity
        for v in stride(from: 0.0, through: 2000, by: 50) {
            let w = StrokeWidth.target(speed: v)
            #expect(w <= last); last = w
        }
        #expect(near(StrokeWidth.next(previous: 34, speed: 5000), 34 + (14 - 34) * 0.35))
    }

    @Test func strokeKeepsSpacedTimestampedSamples() {
        var s = PaintStroke(index: 0)
        let a1 = s.add(Vec2(10, 10), at: 0)
        let a2 = s.add(Vec2(11, 10), at: 0.01)            // closer than minSpacing
        let a3 = s.add(Vec2(13, 10), at: 0.02)
        #expect(a1 && !a2 && a3)
        #expect(s.points.map(\.time) == [0, 0.02])
        #expect(near(s.speed, 150))
        // Fast flicks thin the brush, step by step.
        for i in 1...20 { s.add(Vec2(13 + Double(i) * 30, 10), at: 0.02 + Double(i) / 60) }
        #expect(s.points.last!.width < 16)
        #expect(zip(s.points, s.points.dropFirst()).allSatisfy { $0.time <= $1.time })
        s.end(at: 1)
        #expect(!s.isActive && s.endTime == 1)
        let late = s.add(Vec2(500, 10), at: 2)
        #expect(!late)
        #expect(s.points.count < 22 && s.points.count >= 3)   // straight, but the thinning width profile is kept
        let w = s.points.map(\.width)
        #expect(zip(w, w.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(s.direction == Vec2(1, 0))
    }

    @Test func simplificationKeepsCornersAndRespectsEpsilon() {
        func pt(_ x: Double, _ y: Double, _ w: Double = 20) -> StrokePoint { StrokePoint(position: Vec2(x, y), time: x, width: w) }
        let line = (0...10).map { pt(Double($0) * 5, Double($0 % 2) * 0.4) }
        #expect(StrokeSimplifier.simplify(line).count == 2)
        // Same line, but the width swells mid-stroke: the swell is kept.
        let swell = (0...10).map { pt(Double($0) * 5, 0, 20 + 8 * sin(Double($0) / 10 * .pi)) }
        let ss = StrokeSimplifier.simplify(swell)
        #expect(ss.count > 2 && ss.contains { $0.width > 27.9 })
        for p in swell {
            let i = ss.lastIndex { $0.position.x <= p.position.x }!, j = min(i + 1, ss.count - 1)
            let u = j == i ? 0 : (p.position.x - ss[i].position.x) / (ss[j].position.x - ss[i].position.x)
            #expect(abs(p.width - (ss[i].width + (ss[j].width - ss[i].width) * u)) <= StrokeSimplifier.widthTolerance + 1e-9)
        }
        let corner = (0...10).map { pt(Double($0) * 5, 0) } + (1...10).map { pt(50, Double($0) * 5) }
        let s = StrokeSimplifier.simplify(corner)
        #expect(s.map(\.position) == [Vec2(0, 0), Vec2(50, 0), Vec2(50, 50)])
        #expect(s.last!.time == 50 && s.first!.time == 0)
        // Every dropped point lies within epsilon of the simplified polyline.
        let wiggle = (0...60).map { pt(Double($0) * 3, sin(Double($0) * 0.3) * 9) }
        let w = StrokeSimplifier.simplify(wiggle)
        #expect(w.count < wiggle.count && w.count > 4)
        for p in wiggle {
            let d = zip(w, w.dropFirst()).map { StrokeSimplifier.distance(p.position, toSegment: $0.position, $1.position) }.min()!
            #expect(d <= StrokeSimplifier.epsilon + 1e-9)
        }
    }

    @Test func bristlesAreSeededAndSpanTheBrush() {
        var s = PaintStroke(index: 4)
        for i in 0...10 { s.add(Vec2(Double(i) * 10, 50), at: Double(i) / 60) }
        let b = s.bristles
        #expect(b.count == PaintStroke.bristleCount)
        #expect(b == s.bristles)
        var other = PaintStroke(index: 5)
        for i in 0...10 { other.add(Vec2(Double(i) * 10, 50), at: Double(i) / 60) }
        #expect(other.bristles.map(\.alpha) != b.map(\.alpha))
        for (k, br) in b.enumerated() {
            #expect(br.alpha >= 0.35 && br.alpha <= 0.75)
            #expect(near(br.width, s.points.map(\.width).reduce(0, +) / Double(s.points.count) * 0.26))
            for (i, p) in br.points.enumerated() {
                #expect(abs(p.y - 50) <= s.points[i].width * 0.47)
                #expect(near(p.x, s.points[i].position.x, 1e-9))
            }
            if k > 0 { #expect(br.points[3].y > b[k - 1].points[3].y) }   // spread in order across the width
        }
    }
}

@Suite struct MaskTests {
    @Test func falloffIsSoftAroundTheEdge() {
        #expect(PaintCoverage.maskFalloff(distance: 0, halfWidth: 10, softness: 2) == 1)
        #expect(near(PaintCoverage.maskFalloff(distance: 10, halfWidth: 10, softness: 2), 0.5))
        #expect(PaintCoverage.maskFalloff(distance: 12, halfWidth: 10, softness: 2) == 0)
        var last = 1.0
        for d in stride(from: 7.0, through: 13, by: 0.25) {
            let v = PaintCoverage.maskFalloff(distance: d, halfWidth: 10, softness: 2)
            #expect(v <= last); last = v
        }
        #expect(PaintCoverage.maskFalloff(distance: 10.001, halfWidth: 10, softness: 0) == 0)
    }

    @Test func coverageGrowsWithStrokesAndFills() {
        var c = PaintCoverage(size: card)
        #expect(c.columns == 80 && c.rows == 105 && c.fraction == 0)
        c.addSegment(Vec2(0, 210), Vec2(320, 210), widths: 20, 20, softness: 1.5)
        // A 20 pt band across 420 pt is ≈ 4.8 % of the card.
        #expect(c.fraction > 0.04 && c.fraction < 0.056)
        let once = c.fraction
        c.addSegment(Vec2(0, 210), Vec2(320, 210), widths: 20, 20, softness: 1.5)
        #expect(c.fraction == once)                    // max, not sum
        c.addSegment(Vec2(-50, -50), Vec2(-10, -10), widths: 10, 10, softness: 1)
        #expect(c.fraction == once)                    // off-card is ignored
        c.fillAll(); #expect(c.fraction == 1)
        c.clear(); #expect(c.fraction == 0)
    }
}

@Suite struct DryingTests {
    @Test func strokesDryOverTwoSecondsAndEdgesTighten() {
        var m = PaintModel(size: card)
        m.dragChanged(to: Vec2(40, 40), at: 0)
        m.dragChanged(to: Vec2(80, 40), at: 0.05)
        let s0 = m.strokes[0]
        #expect(m.dryProgress(s0) == 0 && m.wetness(s0) == 1 && m.softness(s0) == 6)
        m.dragEnded(at: 0.1)
        m.advance(to: 1.1)
        #expect(near(m.dryProgress(m.strokes[0]), 0.5))
        #expect(near(m.wetness(m.strokes[0]), 0.5) && near(m.softness(m.strokes[0]), 3.75))
        let ev = m.advance(to: 2.1)
        #expect(ev == [.dried(0)])
        #expect(m.softness(m.strokes[0]) == 1.5 && m.wetness(m.strokes[0]) == 0)
        #expect(m.isIdle)
        let e1 = m.advance(to: 3)
        #expect(e1.isEmpty)
    }

    @Test func reduceMotionDriesInstantlyWithoutSmear() {
        var c = PaintModel.Config(); c.reduceMotion = true
        var m = PaintModel(size: card, config: c)
        m.dragChanged(to: Vec2(40, 40), at: 0)
        m.dragChanged(to: Vec2(80, 60), at: 0.05)
        #expect(m.smear == .zero)
        #expect(m.wetness(m.strokes[0]) == 1)         // still wet under the finger
        m.dragEnded(at: 0.1)
        let ev = m.advance(to: 0.1)
        #expect(ev == [.strokeBegan(0), .strokeEnded(0), .dried(0)])
        #expect(m.isIdle)
        m.restoreAll()
        #expect(m.restoreOpacity == 1)
    }

    @Test func smearFollowsTheNewestWetStroke() {
        var m = PaintModel(size: card)
        m.dragChanged(to: Vec2(100, 100), at: 0)
        m.dragChanged(to: Vec2(100, 130), at: 0.05)
        #expect(m.smear == Vec2(0, 3))
        m.dragEnded(at: 0.05)
        m.advance(to: 1.05)
        #expect(near(m.smear.y, 1.5) && m.smear.x == 0)
        m.advance(to: 2.5)
        #expect(m.smear == .zero)
        let offs = PaintShading.smearOffsets(Vec2(3, 0))
        #expect(offs == [Vec2(0, 0), Vec2(-1, 0), Vec2(-2, 0), Vec2(-3, 0)])
        #expect(PaintShading.smearVector(direction: Vec2(0, -10), wetness: 2) == Vec2(0, -3))
    }
}

@Suite struct HighlightTests {
    @Test func flatPaintOnlyHasSheen() {
        #expect(near(PaintShading.highlight(center: 0.8, left: 0.8, right: 0.8, up: 0.8, down: 0.8), 0.08))
        #expect(PaintShading.highlight(center: 0, left: 0, right: 0, up: 0, down: 0) == 0)
    }

    @Test func ridgesFacingTheLightGlint() {
        // Height rising to the right and down tilts the normal toward the top-left light; the
        // glint peaks when the normal meets the half vector (slope ≈ 0.27, 0.36) and falls off past it.
        let toward = PaintShading.highlight(center: 0.5, left: 0.432, right: 0.568, up: 0.41, down: 0.59)
        let steep = PaintShading.highlight(center: 0.5, left: 0.2, right: 0.6, up: 0.3, down: 0.6)
        let away = PaintShading.highlight(center: 0.5, left: 0.6, right: 0.2, up: 0.6, down: 0.3)
        #expect(toward > 0.85)
        #expect(steep > 0.05 && steep < toward)
        #expect(near(away, 0.05))                 // just the sheen
        #expect(PaintShading.highlight(center: 1, left: 0, right: 1, up: 0, down: 1) <= 1)
        #expect(PaintShading.highlight(center: 0.5, left: 0.2, right: 0.6, up: 0.3, down: 0.6, strength: 0) == 0)
    }
}

@Suite struct EventTests {
    @Test func hapticTicksEveryThirdStrokeDebounced() {
        var m = PaintModel(size: card)
        var ticks: [Double] = []
        var t = 0.0
        for k in 0..<6 {
            let ev = paint(&m, from: Vec2(20, 20 + Double(k) * 30), to: Vec2(200, 20 + Double(k) * 30), t0: t, duration: 0.2)
            if ev.contains(.tick) { ticks.append(t) }
            t += 0.5
        }
        #expect(ticks == [1.0, 2.5])
        #expect(m.ticks == 2 && m.finishedStrokes == 6)
        // Three quick taps in a row: the third lands inside tickInterval of the last tick and is dropped.
        var q = PaintModel(size: card)
        for k in 0..<3 { _ = paint(&q, from: Vec2(50, 50), to: Vec2(90, 50), t0: Double(k) * 0.05, duration: 0.02) }
        #expect(q.ticks == 1)
        for k in 3..<6 { _ = paint(&q, from: Vec2(50, 50), to: Vec2(90, 50), t0: 0.15 + Double(k - 3) * 0.05, duration: 0.02) }
        #expect(q.ticks == 1)
    }

    @Test func eventsArriveInOrder() {
        var m = PaintModel(size: card)
        let ev = paint(&m, from: Vec2(20, 20), to: Vec2(300, 400), t0: 0, duration: 0.5)
        #expect(ev.first == .strokeBegan(0))
        #expect(ev.last == .strokeEnded(0))
        #expect(ev.filter { if case .strokeBegan = $0 { return true }; return false }.count == 1)
        #expect(m.percentRestored > 5 && m.percentRestored < 30)
        _ = paint(&m, from: Vec2(300, 20), to: Vec2(20, 400), t0: 1, duration: 0.5)
        let dried = m.advance(to: 4)
        #expect(dried == [.dried(0), .dried(1)])
    }

    @Test func restoreAllAndReset() {
        var m = PaintModel(size: card)
        m.dragChanged(to: Vec2(50, 50), at: 0)
        m.dragChanged(to: Vec2(90, 50), at: 0.1)
        m.restoreAll()                                  // ends the stroke in progress
        #expect(m.activeStroke == nil && m.percentRestored == 100)
        let e2 = m.advance(to: 0.1)
        #expect(e2 == [.strokeBegan(0), .strokeEnded(0), .restoredAll])
        m.advance(to: 0.4)
        #expect(near(m.restoreOpacity, WhimsyMath.easeOutCubic(0.5)))
        #expect(!m.isIdle)
        m.advance(to: 2.2)
        #expect(m.restoreOpacity == 1 && m.isIdle)
        m.reset()
        #expect(m.strokes.isEmpty && m.percentRestored == 0 && m.restoreOpacity == 0)
        let e3 = m.advance(to: 2.3)
        #expect(e3 == [.reset])
        m.dragChanged(to: Vec2(10, 10), at: 2.3)
        #expect(m.strokes[0].index == 1)               // indices keep counting (stable view identity)
    }
}

@Suite struct ShaderMirrorTests {
    @Test func metalConstantsMatchTheCore() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/OilPaintRestore/Resources/OilPaint.metal")
        let src = try String(contentsOf: url, encoding: .utf8)
        var consts: [String: Double] = [:]
        for line in src.split(separator: "\n") where line.hasPrefix("constant ") {
            let parts = line.split(separator: "=")
            let name = String(parts[0].split(separator: " ").last!)
            consts[name] = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;")))
        }
        #expect(consts == [
            "kSmearLength": PaintShading.smearLength, "kSmearTaps": Double(PaintShading.smearTaps),
            "kHeightScale": PaintShading.heightScale, "kShininess": PaintShading.shininess,
            "kGlossStrength": PaintShading.glossStrength, "kSheen": PaintShading.sheen,
        ])
        #expect(src.contains("normalize(float3(-0.45, -0.6, 0.66))"))
        #expect(src.contains("half3(1.0h, 0.98h, 0.94h)"))
        #expect(PaintShading.light == Vec3(-0.45, -0.6, 0.66) && PaintShading.tint == Vec3(1.0, 0.98, 0.94))
        #expect(src.contains("[[ stitchable ]] half4 paintSmear(float2 position, SwiftUI::Layer layer, float2 smear)"))
        #expect(src.contains("[[ stitchable ]] half4 paintGloss(float2 position, SwiftUI::Layer layer, float strength)"))
    }
}
