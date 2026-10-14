import Testing
import Foundation
@testable import ScatterRegroupCore

private let layout = TileLayout(width: 360, height: 520)

/// Steps at 60 fps for `seconds`, collecting (time, index) landings.
private func run(_ m: inout ScatterRegroupModel, seconds: Double) -> [(Double, Int)] {
    var out: [(Double, Int)] = []
    for _ in 0..<Int(seconds * 60) {
        for i in m.step(dt: 1.0 / 60) { out.append((m.time, i)) }
    }
    return out
}

/// The four corners of a tile rotated by `rotation` and scaled by `scale` about `center`.
private func corners(_ l: TileLayout, center: Vec2, rotation: Double, scale: Double) -> [Vec2] {
    let hw = l.tileWidth / 2 * scale, hh = l.tileHeight / 2 * scale
    return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { (x, y) in
        center + Vec2(x * cos(rotation) - y * sin(rotation), x * sin(rotation) + y * cos(rotation))
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test func fourBySixRowMajorInsideBoundsWithoutOverlap() {
        #expect(layout.count == 24)
        #expect(layout.home(1).x > layout.home(0).x && layout.home(1).y == layout.home(0).y)
        #expect(layout.home(4).y > layout.home(0).y && layout.home(4).x == layout.home(0).x)
        for i in 0..<24 {
            let c = corners(layout, center: layout.home(i), rotation: 0, scale: 1)
            #expect(c.allSatisfy { $0.x >= 0 && $0.x <= 360 && $0.y >= 0 && $0.y <= 520 })
            for j in (i + 1)..<24 {
                let d = layout.home(i) - layout.home(j)
                #expect(abs(d.x) >= layout.tileWidth + layout.spacing - 1e-9 || abs(d.y) >= layout.tileHeight + layout.spacing - 1e-9)
            }
        }
    }

    @Test func spacingAndDegenerateSizes() {
        #expect(abs(layout.tileWidth - (360 - 50) / 4) < 1e-12)
        let tiny = TileLayout(columns: 0, rows: -3, width: -10, height: 5)
        #expect(tiny.count == 1 && tiny.tileWidth == 0)
    }
}

@Suite("Scatter targets")
struct ScatterTargetTests {
    @Test(arguments: [1, 2, 3, 42, 9000] as [UInt64])
    func targetsStayInBoundsWithTiltAndScaleLimits(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let tuning = ScatterTuning()
        for _ in 0..<500 {
            let t = layout.scatterTarget(using: &rng)
            #expect(abs(t.rotation) <= 25 * Double.pi / 180 + 1e-12)
            #expect(tuning.scaleRange.contains(t.scale))
            let c = corners(layout, center: t.position, rotation: t.rotation, scale: t.scale)
            #expect(c.allSatisfy { $0.x >= -1e-9 && $0.x <= 360 + 1e-9 && $0.y >= -1e-9 && $0.y <= 520 + 1e-9 })
        }
    }

    @Test func tiltsAndScalesActuallyVary() {
        var rng = SeededRandom(seed: 5)
        let ts = (0..<200).map { _ in layout.scatterTarget(using: &rng) }
        #expect(ts.contains { $0.rotation < -0.3 } && ts.contains { $0.rotation > 0.3 })
        #expect(ts.contains { $0.scale < 0.9 } && ts.contains { $0.scale > 1.1 })
    }

    @Test func rippleDelaysGrowFromTheCentre() {
        let d = layout.rippleDelays(duration: 0.4)
        let order = (0..<24).sorted { layout.distanceFromCenter($0) < layout.distanceFromCenter($1) }
        #expect(zip(order, order.dropFirst()).allSatisfy { d[$0] <= d[$1] + 1e-12 })
        #expect(d.min() == 0 && abs(d.max()! - 0.4) < 1e-12)
        // 4 × 6: the four middle tiles (rows 2–3, columns 1–2) go first, the four corners last.
        #expect([9, 10, 13, 14].allSatisfy { d[$0] == 0 })
        #expect([0, 3, 20, 23].allSatisfy { abs(d[$0] - 0.4) < 1e-12 })
        // Symmetric tiles start together.
        #expect(abs(d[0] - d[23]) < 1e-12 && abs(d[5] - d[18]) < 1e-12)
        #expect(TileLayout(columns: 1, rows: 1, width: 10, height: 10).rippleDelays(duration: 1) == [0])
    }
}

@Suite("Model")
struct ModelTests {
    @Test func stiffnessVariesButIsFixedPerSeed() {
        let a = ScatterRegroupModel(layout: layout, seed: 7), b = ScatterRegroupModel(layout: layout, seed: 7)
        let c = ScatterRegroupModel(layout: layout, seed: 8)
        let ks = a.tiles.map(\.stiffness)
        #expect(ks == b.tiles.map(\.stiffness))
        #expect(ks != c.tiles.map(\.stiffness))
        #expect(ks.allSatisfy { $0 >= 150 * 0.7 && $0 <= 150 * 1.3 })
        #expect(Set(ks).count == 24)
    }

    @Test func startsHomeAndSettled() {
        let m = ScatterRegroupModel(layout: layout)
        #expect(!m.isScattered && m.isSettled)
        #expect(m.tiles.indices.allSatisfy { m.tiles[$0].position == layout.home($0) })
    }

    @Test func scatterFliesOutWithoutLandings() {
        var m = ScatterRegroupModel(layout: layout, seed: 3)
        m.scatter()
        let landings = run(&m, seconds: 3)
        #expect(landings.isEmpty)
        #expect(m.isSettled && m.isScattered)
        #expect(m.tiles.indices.allSatisfy { (m.tiles[$0].position - m.targets[$0].position).length < 0.05 })
        #expect(m.tiles.contains { abs($0.rotation) > 0.2 })
    }

    @Test func regroupLandsEveryTileExactlyOnceInARipple() {
        var m = ScatterRegroupModel(layout: layout, seed: 3)
        m.scatter(); _ = run(&m, seconds: 3)
        m.regroup()
        #expect(m.pendingLandings.count == 24)
        let landings = run(&m, seconds: 3)
        #expect(landings.map(\.1).sorted() == Array(0..<24))
        #expect(m.pendingLandings.isEmpty && m.isSettled && !m.isScattered)
        #expect(m.tiles.indices.allSatisfy { (m.tiles[$0].position - layout.home($0)).length < 0.05 })
        #expect(m.tiles.allSatisfy { abs($0.rotation) < 1e-3 && abs($0.scale - 1) < 1e-3 })
        // Ripple: on average the centre four land before the corner four.
        let when = Dictionary(uniqueKeysWithValues: landings.map { ($0.1, $0.0) })
        let mean = { (ids: [Int]) in ids.map { when[$0]! }.reduce(0, +) / Double(ids.count) }
        #expect(mean([9, 10, 13, 14]) < mean([0, 3, 20, 23]))
    }

    @Test func centreTilesHoldStillUntilTheirDelayEnds() {
        var m = ScatterRegroupModel(layout: layout, seed: 3)
        m.scatter(); _ = run(&m, seconds: 3)
        m.regroup()
        let corner = m.tiles[0].position
        _ = run(&m, seconds: 0.2)                 // corner delay is 0.38 s
        #expect(m.tiles[0].position == corner)
        #expect(m.tiles[9].position != m.targets[9].position || m.tiles[9].velocity != .zero)
    }

    @Test func springsOvershootALittle() {
        var m = ScatterRegroupModel(layout: layout, seed: 3)
        m.scatter(); _ = run(&m, seconds: 3)
        m.regroup()
        var maxScaleBelowOne = 0.0
        for _ in 0..<180 { m.step(dt: 1.0 / 60); maxScaleBelowOne = max(maxScaleBelowOne, m.tiles.map { 1 - $0.scale }.max()!) }
        // Some tile scattered larger than 1 swings below 1 on the way home (ζ 0.62).
        #expect(maxScaleBelowOne > 0.005)
    }

    @Test func eachScatterIsNewButTheSequenceIsSeeded() {
        var a = ScatterRegroupModel(layout: layout, seed: 11), b = ScatterRegroupModel(layout: layout, seed: 11)
        a.scatter(); b.scatter()
        let first = a.targets
        #expect(first == b.targets)
        a.regroup(); a.scatter()
        #expect(a.targets != first)
    }

    @Test func interruptingAScatterRegroupsCleanly() {
        var m = ScatterRegroupModel(layout: layout, seed: 4)
        m.scatter(); _ = run(&m, seconds: 0.12)
        m.toggle()                               // regroup mid-flight
        let away = m.pendingLandings
        #expect(!away.isEmpty)
        let landings = run(&m, seconds: 3)
        // Exactly the tiles that had left home land, once each; tiles still in their launch
        // jitter never left, so they don't tick.
        #expect(landings.map(\.1).sorted() == away.sorted())
        #expect(m.pendingLandings.isEmpty && m.isSettled && !m.isScattered)
    }

    @Test func nonAnimatedTogglesSnap() {
        var m = ScatterRegroupModel(layout: layout, seed: 4)
        m.toggle(animated: false)
        #expect(m.isScattered && m.isSettled)
        #expect(m.tiles.indices.allSatisfy { m.tiles[$0].position == m.targets[$0].position })
        m.toggle(animated: false)
        #expect(!m.isScattered && m.isSettled && m.pendingLandings.isEmpty)
    }

    @Test func resizeKeepsTilesInPlace() {
        var m = ScatterRegroupModel(layout: layout, seed: 4)
        m.resize(width: 300, height: 400)
        #expect(m.layout.width == 300 && m.isSettled)
        #expect(m.tiles.indices.allSatisfy { m.tiles[$0].position == m.layout.home($0) })
        m.scatter(animated: false)
        let before = m.targets[5].position
        m.resize(width: 600, height: 400)
        #expect(abs(m.targets[5].position.x - before.x * 2) < 1e-9 && m.isSettled)
    }

    @Test func deterministicAndSafeSteps() {
        var a = ScatterRegroupModel(layout: layout, seed: 21), b = ScatterRegroupModel(layout: layout, seed: 21)
        a.scatter(); b.scatter()
        _ = run(&a, seconds: 1); _ = run(&b, seconds: 1)
        #expect(a == b)
        let before = a
        a.step(dt: 0); a.step(dt: -1); a.step(dt: .nan)
        #expect(a == before)
        a.step(dt: 50)
        #expect(abs(a.time - before.time - 0.1) < 1e-9)
    }

    @Test func frameRateIndependentEnough() {
        var a = ScatterRegroupModel(layout: layout, seed: 2), b = ScatterRegroupModel(layout: layout, seed: 2)
        a.scatter(); b.scatter()
        for _ in 0..<30 { a.step(dt: 1.0 / 60) }
        for _ in 0..<60 { b.step(dt: 1.0 / 120) }
        #expect(a.tiles.indices.allSatisfy { (a.tiles[$0].position - b.tiles[$0].position).length < 0.5 })
    }
}

@Suite("Landing throttle")
struct LandingThrottleTests {
    @Test func limitsRate() {
        var t = LandingThrottle(minimumInterval: 0.05)
        let fires = [0, 0.01, 0.049, 0.05, 0.2].map { t.shouldFire(at: $0) }
        #expect(fires == [true, false, false, true, true])
        #expect(t.fired == 3)
    }

    @Test func aFullRegroupTicksSeveralButFewerThanTwentyFourTimes() {
        var m = ScatterRegroupModel(layout: layout, seed: 3)
        m.scatter(); _ = run(&m, seconds: 3)
        m.regroup()
        var throttle = LandingThrottle()
        for (time, _) in run(&m, seconds: 3) { _ = throttle.shouldFire(at: time) }
        #expect(throttle.fired >= 4 && throttle.fired < 24)
    }
}
