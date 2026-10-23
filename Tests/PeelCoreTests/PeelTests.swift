import Testing
@testable import PeelCore

private let square = Polygon([Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)])
private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
private func near(_ a: Vec2, _ b: Vec2, _ eps: Double = 1e-9) -> Bool { a.distance(to: b) <= eps }

@Suite struct FoldGeometryTests {
    @Test func foldIsThePerpendicularBisector() throws {
        let f = try #require(FoldLine(grab: Vec2(100, 0), finger: Vec2(60, 40)))
        #expect(near(f.point, Vec2(80, 20)))
        #expect(near(f.normal.length, 1))
        #expect(near(f.normal.dot(Vec2(-40, 40).normalized), 1))
        #expect(near(f.tangent.dot(f.normal), 0))
        // Grab and finger are mirror images; the crease itself is fixed.
        #expect(near(f.reflect(Vec2(100, 0)), Vec2(60, 40), 1e-9))
        #expect(near(f.reflect(f.point + f.tangent * 17), f.point + f.tangent * 17))
        #expect(near(f.reflect(f.reflect(Vec2(3, 77))), Vec2(3, 77)))
        #expect(f.signedDistance(Vec2(100, 0)) < 0 && f.signedDistance(Vec2(60, 40)) > 0)
        #expect(FoldLine(grab: Vec2(1, 1), finger: Vec2(1, 1)) == nil)
    }

    @Test func peelingACornerLiftsATriangle() throws {
        // Corner (100, 0) dragged to (60, 40): the crease runs x − y = 60, lifting the
        // triangle (60,0) (100,0) (100,40) — area 800 of 10 000.
        let p = PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(60, 40))
        #expect(near(p.fraction, 0.08))
        #expect(near(p.lifted.area, 800) && near(p.flat.area, 9200))
        #expect(near(p.flap.area, p.lifted.area))
        // The flap is the mirror image: the corner lands on the finger.
        #expect(p.flap.points.contains { near($0, Vec2(60, 40), 1e-9) })
        let crease = try #require(p.crease)
        #expect(Set([crease.0, crease.1].map { [($0.x * 1e6).rounded(), ($0.y * 1e6).rounded()] }) ==
                Set([[60e6, 0], [100e6, 40e6]]))
        // Back face lies on the finger side of the crease.
        let fold = try #require(p.fold)
        #expect(p.flap.points.allSatisfy { fold.signedDistance($0) >= -1e-9 })
    }

    @Test func fractionGrowsWithTheDragAndReachesHalfOnTheDiagonal() {
        var last = -1.0
        for k in stride(from: 0.0, through: 1.0, by: 0.05) {
            let f = PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(100 - 100 * k, 100 * k)).fraction
            #expect(f >= last - 1e-12)
            last = f
        }
        // Dragging the corner onto the opposite corner folds along the other diagonal: half.
        #expect(near(PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(0, 100)).fraction, 0.5))
        #expect(near(PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(-100, 200)).fraction, 1))
        // Dragging outward lifts nothing.
        #expect(PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(140, -40)).fraction == 0)
        #expect(PeelState.peel(square, grab: Vec2(100, 0), finger: Vec2(100, 0)) == .flat(square))
    }

    @Test func roundedRectAndClipping() {
        let r = Polygon.roundedRect(center: Vec2(0, 0), width: 180, height: 180, cornerRadius: 34, segments: 24)
        let exact = 180.0 * 180 - (4 - .pi) * 34 * 34
        #expect(abs(r.area - exact) / exact < 1e-3)
        #expect(near(r.centroid, .zero, 1e-9))
        let half = r.clipped { $0.x }          // keep x ≥ 0
        #expect(abs(half.area - r.area / 2) < 1e-6)
        #expect(r.clipped { _ in -1 }.isEmpty)
        #expect(near(square.centroid, Vec2(50, 50)))
    }
}

@Suite struct ReleaseTests {
    @Test func velocityTracker() {
        var t = VelocityTracker(window: 0.08)
        #expect(t.velocity(at: 0) == .zero)
        for i in 0...10 { t.add(Vec2(Double(i) * 10, 0), at: Double(i) / 100) }   // 1000 pt/s
        #expect(near(t.velocity(at: 0.1).x, 1000, 1e-6))
        #expect(t.velocity(at: 0.1 + 0.2) == .zero)            // held still since
        t.add(Vec2(0, 0), at: 0.05)                             // time went backwards: reset
        #expect(t.samples.count == 1)
    }

    @Test func releaseDecision() {
        let r = PeelRules(), n = Vec2(-1, 1).normalized
        #expect(r.decide(fraction: 0.2, velocity: .zero, peelDirection: n) == .springBack)
        #expect(r.decide(fraction: 0.49, velocity: n * 1500, peelDirection: n) == .springBack)
        #expect(r.decide(fraction: 0.5, velocity: .zero, peelDirection: n) == .popOff)
        #expect(r.decide(fraction: 0.8, velocity: .zero, peelDirection: n) == .popOff)
        #expect(r.decide(fraction: 0.1, velocity: n * 2100, peelDirection: n) == .tear)
        // Fast but sideways, or backwards: not a yank.
        #expect(r.decide(fraction: 0.1, velocity: n.perpendicular * 5000, peelDirection: n) == .springBack)
        #expect(r.decide(fraction: 0.7, velocity: n * -5000, peelDirection: n) == .popOff)
        // Needs something lifted to grip.
        #expect(!r.shouldTear(fraction: 0.01, velocity: n * 9000, peelDirection: n))
        #expect(!r.shouldTear(fraction: 0.3, velocity: n * 9000, peelDirection: nil))
    }

    @Test func tearSplitsIntoTwoFittingPieces() throws {
        let shape = Polygon.roundedRect(center: Vec2(0, 0), width: 180, height: 180, cornerRadius: 34)
        let fold = try #require(FoldLine(grab: Vec2(80, -80), finger: Vec2(0, 0)))
        let a = try #require(TearGeometry.pieces(of: shape, fold: fold, seed: 9))
        let b = try #require(TearGeometry.pieces(of: shape, fold: fold, seed: 9))
        #expect(a.lifted == b.lifted && a.stuck == b.stuck)
        #expect(near(a.lifted.area + a.stuck.area, shape.area, 1e-6))
        #expect(a.lifted.area > 0 && a.stuck.area > 0)
        // Jagged: 7 teeth on the shared edge, the same points in both pieces.
        let shared = Set(a.lifted.points.map { [$0.x, $0.y] }).intersection(a.stuck.points.map { [$0.x, $0.y] })
        #expect(shared.count == 7 + 2)
        let off = a.lifted.points.map { abs(fold.signedDistance($0)) }.filter { $0 > 1e-6 && $0 < 6 }
        #expect(off.count >= 7 && off.allSatisfy { $0 >= 2 && $0 <= 5 })
        let c = try #require(TearGeometry.pieces(of: shape, fold: fold, seed: 10))
        #expect(c.lifted != a.lifted)
        // Nothing to tear if the crease misses the sticker.
        let miss = try #require(FoldLine(grab: Vec2(300, 0), finger: Vec2(400, 0)))
        #expect(TearGeometry.pieces(of: shape, fold: miss, seed: 1) == nil)
    }
}

@Suite struct TumbleTests {
    @Test func tumbleSpinsFallsAndFades() {
        let phys = TumblePhysics()
        var rng = SeededRandom(seed: 3)
        var b = phys.launch(at: Vec2(0, 0), direction: Vec2(1, -1), release: .zero, rng: &rng)
        #expect(b.velocity.y < 0 && b.velocity.x > 0)          // kicked up and along the peel
        #expect(b.spin > 0)
        #expect(phys.opacity(b) == 1 && phys.scale(b) == 1)
        var apex = b.position.y
        for _ in 0..<60 { phys.step(&b, dt: 1.0 / 60); apex = min(apex, b.position.y) }
        #expect(near(b.age, 1, 1e-9))
        #expect(b.position.y > apex)                             // gravity won
        #expect(b.angle > 3)                                     // a good half-turn or more
        #expect(phys.opacity(b) == 0 && phys.isFinished(b))
        // Peeling leftward spins the other way.
        let left = phys.launch(at: .zero, direction: Vec2(-1, 0), release: .zero, rng: &rng)
        #expect(left.spin < 0)
    }

    @Test func tumbleIsFrameRateIndependentAndReducible() {
        let phys = TumblePhysics()
        var r1 = SeededRandom(seed: 5), r2 = SeededRandom(seed: 5)
        var a = phys.launch(at: .zero, direction: Vec2(0, -1), release: Vec2(400, 0), rng: &r1)
        var b = phys.launch(at: .zero, direction: Vec2(0, -1), release: Vec2(400, 0), rng: &r2)
        for _ in 0..<120 { phys.step(&a, dt: 1.0 / 120) }
        for _ in 0..<30 { phys.step(&b, dt: 1.0 / 30) }
        #expect(near(a.position, b.position, 1e-6) && near(a.angle, b.angle, 1e-9))
        let calm = TumblePhysics(reduceMotion: true)
        var c = calm.launch(at: Vec2(5, 5), direction: Vec2(1, 0), release: Vec2(900, 0), rng: &r1)
        calm.step(&c, dt: 0.075)
        calm.step(&c, dt: 0.075)
        #expect(c.position == Vec2(5, 5) && c.angle == 0 && near(calm.opacity(c), 0.5))
    }
}

@Suite struct ModelTests {
    private func run(_ m: inout PeelModel, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { m.step(1.0 / 60) }
    }

    @Test func grabOnlyNearACorner() {
        var m = PeelModel(center: Vec2(200, 400))
        do { let grabbed = m.begin(at: Vec2(200, 400), time: 0); #expect(!grabbed) }           // the middle
        do { let grabbed = m.begin(at: Vec2(200, 310), time: 0); #expect(!grabbed) }           // an edge midpoint
        do { let grabbed = m.begin(at: m.corners[0] + Vec2(-10, 8), time: 0); #expect(grabbed) }
        #expect(m.phase == .peeling && m.grabs == 1)
        #expect(m.peel?.fraction == 0)                          // no jump on touch-down
    }

    @Test func shortPeelSpringsBackFlat() throws {
        var m = PeelModel(center: Vec2(200, 400))
        let c = m.corners[0]
        m.begin(at: c, time: 0)
        for i in 1...30 { m.move(to: c + Vec2(-2, 2) * Double(i), time: Double(i) / 60) }
        let f = try #require(m.peel?.fraction)
        #expect(f > 0.05 && f < 0.5)
        m.end(time: 0.5 + 0.2)
        #expect(m.phase == .springingBack)
        run(&m, seconds: 1.5)
        #expect(m.phase == .idle && m.peel?.fraction == 0 && m.pops == 0)
    }

    @Test func pastHalfwayPopsOffAndRespawns() throws {
        var m = PeelModel(center: Vec2(200, 400))
        let c = m.corners[0], far = m.corners[2]
        m.begin(at: c, time: 0)
        for i in 1...60 { m.move(to: Vec2.lerp(c, far, 1.04 * Double(i) / 60), time: Double(i) / 60) }
        #expect((m.peel?.fraction ?? 0) >= 0.5)
        m.end(time: 1.2)
        try #require(m.pieces.count == 1)
        #expect(m.phase == .popped && m.pops == 1 && m.pieces.count == 1 && m.peel == nil)
        let start = m.pieces[0].body.position
        run(&m, seconds: 0.4)
        #expect(m.pieces[0].body.angle != 0 && m.pieces[0].body.position != start)
        #expect((m.pieces[0].peel.fraction) < 0.2)               // relaxed flat in the air
        var guardSteps = 0
        while m.phase == .popped, guardSteps < 600 { m.step(1.0 / 60); guardSteps += 1 }
        #expect(m.phase == .respawning && m.designIndex == 1)
        #expect(m.appear < 0.2)
        #expect(Double(guardSteps) / 60 < 1.2)                   // gone within ~1.3 s of the pop
        run(&m, seconds: 1.0)
        #expect(m.phase == .idle && m.appear == 1 && m.design == StickerDesign.all[1])
    }

    @Test func fastYankTearsAndLeavesResidue() {
        var m = PeelModel(center: Vec2(200, 400))
        let c = m.corners[2], dir = (m.center - c).normalized
        m.begin(at: c, time: 0)
        for i in 1...10 { m.move(to: c + dir * (2 * Double(i)), time: Double(i) / 60) }   // slow: 120 pt/s
        #expect(m.phase == .peeling)
        var t = 10.0 / 60
        for _ in 0..<6 where m.phase == .peeling { t += 1.0 / 120; m.move(to: m.finger.value + dir * 30, time: t) }  // 3600 pt/s
        #expect(m.phase == .torn && m.tears == 1 && m.pieces.count == 2)
        #expect(m.residueOpacity > 0.29)
        // Each half knows where the sticker's centre is, so its artwork lines up.
        for p in m.pieces { #expect(near(p.body.position + p.artOffset, m.center, 1e-9)) }
        let a0 = m.pieces[0].body.position, b0 = m.pieces[1].body.position
        run(&m, seconds: 0.1)
        #expect(m.pieces[0].body.position != a0 && m.pieces[1].body.position == b0)   // stuck half waits
        run(&m, seconds: 1.0)
        #expect(m.residueOpacity > 0 && m.residueOpacity < 0.3)
        run(&m, seconds: 1.0)
        #expect(m.phase == .respawning && m.residueOpacity == 0)
    }

    @Test func accessibilityPopAndGuards() {
        var m = PeelModel(center: Vec2(200, 400))
        m.move(to: Vec2(0, 0), time: 0)
        m.end(time: 0)
        #expect(m.phase == .idle)
        m.popNow()
        #expect(m.phase == .popped && m.pops == 1)
        do { let grabbed = m.begin(at: m.corners[0], time: 0); #expect(!grabbed) }
        m.setCenter(Vec2(10, 10))
        #expect(m.center == Vec2(200, 400))
    }
}
