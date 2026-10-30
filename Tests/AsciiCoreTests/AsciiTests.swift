import Testing
import Foundation
@testable import AsciiCore

private func near(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

/// Steps a model at 60 Hz up to `t`, returning every event.
private func run(_ m: inout AsciiModel, from: Double = 0, to t: Double) -> [AsciiEvent] {
    var out: [AsciiEvent] = []
    var f = Int((from * 60).rounded(.up))
    while Double(f) / 60 <= t + 1e-9 { out += m.advance(to: Double(f) / 60); f += 1 }
    return out
}

private func text(_ cells: [AsciiCell]) -> String { String(cells.map(\.glyph)) }

@Suite("Image sampling") struct ImageTests {
    @Test func boxFilterAveragesWholeBlocks() {
        let img = AsciiImage(width: 2, height: 2, pixels: [AsciiRGB(0, 0, 0), AsciiRGB(1, 0, 0), AsciiRGB(0, 1, 0), AsciiRGB(1, 1, 1)])
        let one = img.downsample(cols: 1, rows: 1)
        #expect(one.width == 1 && one.height == 1)
        #expect(near(one[0, 0].r, 0.5) && near(one[0, 0].g, 0.5) && near(one[0, 0].b, 0.25))
    }

    @Test func constantImageStaysConstantAtAnyRatio() {
        let img = AsciiImage(width: 192, height: 192, fill: AsciiRGB(0.2, 0.5, 0.9))
        for cols in [24, 37, 48, 72] {
            let s = img.downsample(cols: cols, rows: cols)
            #expect(s.pixels.allSatisfy { near($0.r, 0.2) && near($0.g, 0.5) && near($0.b, 0.9) })
        }
    }

    @Test func fractionalCellsWeighEdgePixelsByCoverage() {
        // 3 pixels wide into 2 cells: the middle pixel is split half and half.
        let img = AsciiImage(width: 3, height: 1, pixels: [AsciiRGB(0, 0, 0), AsciiRGB(0.6, 0, 0), AsciiRGB(0.9, 0, 0)])
        let s = img.downsample(cols: 2, rows: 1)
        #expect(near(s[0, 0].r, (0 * 1 + 0.6 * 0.5) / 1.5))
        #expect(near(s[1, 0].r, (0.6 * 0.5 + 0.9 * 1) / 1.5))
    }

    @Test func downsamplePreservesTheMeanColour() {
        let img = AsciiCover.image()
        let mean = { (i: AsciiImage) in i.pixels.reduce(0) { $0 + $1.r } / Double(i.pixels.count) }
        for cols in [24, 48, 72] { #expect(near(mean(img.downsample(cols: cols, rows: cols)), mean(img), 1e-9)) }
    }

    @Test func coverIsDeterministicColourfulAndInRange() {
        let a = AsciiCover.image(), b = AsciiCover.image()
        #expect(a == b)
        #expect(a.pixels.allSatisfy { (0...1).contains($0.r) && (0...1).contains($0.g) && (0...1).contains($0.b) })
        let sun = AsciiCover.color(0.5, 0.25), hill = AsciiCover.color(0.5, 0.97), top = AsciiCover.color(0.3, 0.02)
        #expect(AsciiRamp.luminance(sun) > 0.6 && AsciiRamp.luminance(hill) < 0.15 && AsciiRamp.luminance(top) < 0.2)
        // Slats: the lower sun has gaps that show the sky.
        let lower = stride(from: 0.41, to: 0.62, by: 0.004).map { AsciiCover.color(0.5, $0) }
        #expect(Set(lower.map { $0.g }).count > 8)
        #expect(Set(a.pixels.map { "\($0.r),\($0.g),\($0.b)" }).count > 150)
    }

    @Test func gridHasTonesAndTintsPerCell() {
        let g = AsciiGrid(source: AsciiCover.image(), cols: 48)
        #expect(g.cols == 48 && g.colors.count == 2304 && g.tones.count == 2304 && g.tints.count == 2304)
        #expect(g.tones.min()! < 0.08 && g.tones.max()! > 0.7)
    }
}

@Suite("Ramp") struct RampTests {
    @Test func luminanceWeightsAndGamma() {
        #expect(near(AsciiRamp.luminance(AsciiRGB(1, 1, 1)), 1))
        #expect(near(AsciiRamp.luminance(AsciiRGB(0, 1, 0)), 0.7152))
        #expect(AsciiRamp.luminance(AsciiRGB(0, 1, 0)) > AsciiRamp.luminance(AsciiRGB(1, 0, 0)))
        #expect(AsciiRamp.luminance(AsciiRGB(1, 0, 0)) > AsciiRamp.luminance(AsciiRGB(0, 0, 1)))
        // gamma 0.8 lifts the mids and leaves the ends.
        #expect(near(AsciiRamp.tone(AsciiRGB(0, 0, 0)), 0) && near(AsciiRamp.tone(AsciiRGB(1, 1, 1)), 1))
        #expect(AsciiRamp.tone(AsciiRGB(0.25, 0.25, 0.25)) > 0.25)
    }

    @Test func rampMapsDarkToBrightAndClamps() {
        #expect(String(AsciiRamp.ramp) == " .:-=+*#%@")
        #expect(AsciiRamp.glyph(tone: 0) == " " && AsciiRamp.glyph(tone: 1) == "@")
        #expect(AsciiRamp.glyph(tone: -3) == " " && AsciiRamp.glyph(tone: 7) == "@")
        let idx = stride(from: 0.0, through: 1.0, by: 0.01).map { AsciiRamp.index(tone: $0) }
        #expect(idx == idx.sorted() && Set(idx).count == 10)
        #expect(AsciiRamp.glyph(tone: 0.5) == "=" || AsciiRamp.glyph(tone: 0.5) == "+")
    }

    @Test func extendedSetContainsTheRampAndMore() {
        #expect(AsciiRamp.extended.count > AsciiRamp.ramp.count + 10)
        #expect(Array(AsciiRamp.extended.prefix(10)) == AsciiRamp.ramp)
        #expect(Set(AsciiRamp.extended).count == AsciiRamp.extended.count)
    }

    @Test func tintBrightensDimCellsButKeepsHue() {
        let dim = AsciiRamp.tint(AsciiRGB(0.05, 0.10, 0.20))
        #expect(near(max(dim.r, dim.g, dim.b), 0.20 / 0.45))
        #expect(near(dim.b / dim.g, 2))
        let bright = AsciiRamp.tint(AsciiRGB(0.9, 0.5, 0.1))
        #expect(near(bright.r, 1) && near(bright.g, 0.5 / 0.9))
        #expect(AsciiRamp.tint(AsciiRGB(0, 0, 0)) == AsciiRGB(0, 0, 0))
    }

    @Test func hashIsSeededStatelessAndSpread() {
        #expect(AsciiHash.hash(1, 2, 3) == AsciiHash.hash(1, 2, 3))
        #expect(AsciiHash.hash(1, 2, 3) != AsciiHash.hash(2, 2, 3))
        #expect(AsciiHash.hash(1, 2, 3) != AsciiHash.hash(1, 3, 3))
        let u = (0..<4000).map { AsciiHash.unit(AsciiHash.hash(9, UInt32($0), 0)) }
        #expect(u.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = u.reduce(0, +) / Double(u.count)
        #expect(abs(mean - 0.5) < 0.03)
    }
}

@Suite("Fields") struct FieldTests {
    @Test func shimmerIsBoundedAndSlow() {
        let s = AsciiShimmer()
        var lo = 0.0, hi = 0.0
        for i in 0..<400 { let v = s.value(u: Double(i % 20) / 20, v: Double(i / 20) / 20, t: Double(i) * 0.1, energy: 1); lo = min(lo, v); hi = max(hi, v) }
        #expect(lo >= -s.amplitude && hi <= s.amplitude && lo < -0.1 && hi > 0.1)
        #expect(near(s.value(u: 0.3, v: 0.6, t: 2, energy: 1), s.value(u: 0.3, v: 0.6, t: 2 + s.period, energy: 1), 1e-9))
        #expect(s.value(u: 0.3, v: 0.6, t: 2, energy: 0) == 0)
        #expect(near(s.value(u: 0.3, v: 0.6, t: 2, energy: 0.5), 0.5 * s.value(u: 0.3, v: 0.6, t: 2, energy: 1)))
    }

    @Test func shimmerPhaseVariesAcrossTheArt() {
        let s = AsciiShimmer()
        let phases = [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9), (0.5, 0.5)].map { s.phase(u: $0.0, v: $0.1, t: 0) }
        #expect(Set(phases.map { ($0 * 1000).rounded() }).count == 5)
        // One period advances the phase by 2π.
        #expect(near(s.phase(u: 0.4, v: 0.4, t: s.period) - s.phase(u: 0.4, v: 0.4, t: 0), 2 * Double.pi))
    }

    @Test func cellStatesGoCalmScrambledSettled() {
        let d = 0.5, h = 0.5
        let a = AsciiScramble.startDelay(distance: d), r = AsciiScramble.resolveTime(distance: d, jitter: h)
        #expect(AsciiScramble.state(elapsed: a - 0.01, distance: d, jitter: h) == .calm)
        #expect(AsciiScramble.state(elapsed: a, distance: d, jitter: h) == .scrambled)
        #expect(AsciiScramble.state(elapsed: r - 0.01, distance: d, jitter: h) == .scrambled)
        #expect(AsciiScramble.state(elapsed: r, distance: d, jitter: h) == .settled(flash: 1))
        if case .settled(let f) = AsciiScramble.state(elapsed: r + AsciiScramble.flashDuration / 2, distance: d, jitter: h) { #expect(near(f, 0.5)) } else { Issue.record("expected settled") }
        #expect(AsciiScramble.state(elapsed: r + 1, distance: d, jitter: h) == .settled(flash: 0))
    }

    @Test func resolveIsAWaveFromTheOriginWithBoundedJitter() {
        // Nearer cells resolve before farther ones (jitter smaller than the wave gap).
        #expect(AsciiScramble.resolveTime(distance: 0.2, jitter: 1) < AsciiScramble.resolveTime(distance: 0.2 + 0.2, jitter: 0))
        #expect(AsciiScramble.resolveTime(distance: 0, jitter: 0) == AsciiScramble.hold)
        let last = AsciiScramble.resolveTime(distance: 1, jitter: 1)
        #expect(near(last + AsciiScramble.flashDuration, AsciiScramble.total))
        #expect(AsciiScramble.startDelay(distance: 1) < AsciiScramble.hold)           // everything scrambles before anything resolves
    }

    @Test func maxDistanceIsTheFarCorner() {
        #expect(near(AsciiScramble.maxDistance(from: Vec2(0, 0)), 2.0.squareRoot()))
        #expect(near(AsciiScramble.maxDistance(from: Vec2(0.5, 0.5)), (0.5).squareRoot()))
        #expect(near(AsciiScramble.maxDistance(from: Vec2(0.25, 0.5)), Vec2(0.25, 0.5).distance(to: Vec2(1, 0))))
    }

    @Test func randomGlyphsAreSeededAndChangeOverTime() {
        let a = AsciiScramble.randomGlyphIndex(seed: 5, epoch: 1, cell: 10, elapsed: 0.5)
        #expect(a == AsciiScramble.randomGlyphIndex(seed: 5, epoch: 1, cell: 10, elapsed: 0.5))
        #expect(a == AsciiScramble.randomGlyphIndex(seed: 5, epoch: 1, cell: 10, elapsed: 0.5 + 0.5 / AsciiScramble.rate))
        let seq = (0..<60).map { AsciiScramble.randomGlyphIndex(seed: 5, epoch: 1, cell: 10, elapsed: Double($0) / AsciiScramble.rate) }
        #expect(Set(seq).count > 12)
        #expect(seq.allSatisfy { (0..<AsciiRamp.extended.count).contains($0) })
        #expect(AsciiScramble.randomGlyphIndex(seed: 5, epoch: 2, cell: 10, elapsed: 0.5) != a || AsciiScramble.randomGlyphIndex(seed: 5, epoch: 2, cell: 11, elapsed: 0.5) != a)
    }
}

@Suite("Density") struct DensityTests {
    @Test func dragMapsToColumnsAndClamps() {
        let d = AsciiDensity.self
        #expect(d.columns(start: 48, translation: 0) == 48)
        #expect(d.columns(start: 48, translation: -d.dragRange) == 72)
        #expect(d.columns(start: 48, translation: d.dragRange) == 24)
        #expect(d.columns(start: 48, translation: -10_000) == 72 && d.columns(start: 48, translation: 10_000) == 24)
        #expect(d.columns(start: 24, translation: -d.dragRange / 2) == 48)
        #expect(d.columns(start: 99, translation: 0) == 72 && d.columns(start: 1, translation: 0) == 24)
    }

    @Test func draggingUpIsFinerAndItIsMonotone() {
        let cols = stride(from: 200.0, through: -200.0, by: -10).map { AsciiDensity.columns(start: 48, translation: $0) }
        #expect(cols == cols.sorted())
        #expect(cols.first! < 48 && cols.last! > 48)
    }

    @Test func stepsClampAndRoundTrip() {
        #expect(AsciiDensity.stepped(48, up: true) == 56 && AsciiDensity.stepped(48, up: false) == 40)
        #expect(AsciiDensity.stepped(70, up: true) == 72 && AsciiDensity.stepped(26, up: false) == 24)
        #expect(AsciiDensity.stepped(AsciiDensity.stepped(48, up: true), up: false) == 48)
    }

    @Test func typeSizeFollowsTheGrid() {
        #expect(near(AsciiDensity.cellSize(columns: 48, side: 300), 6.25))
        #expect(AsciiDensity.fontSize(columns: 24, side: 300) > 2 * AsciiDensity.fontSize(columns: 72, side: 300) * 0.99)
        #expect(near(AsciiDensity.fontSize(columns: 60, side: 300), 5 * 1.3))
        #expect(AsciiDensity.label(24) == "crunchy" && AsciiDensity.label(48) == "medium" && AsciiDensity.label(72) == "fine")
    }
}

@Suite("Player") struct PlayerTests {
    @Test func advancesSeeksAndStopsAtTheEnd() {
        var p = AsciiPlayer(duration: 100, position: 90)
        #expect(p.advance(by: 5) == false && near(p.position, 95) && near(p.progress, 0.95))
        #expect(p.advance(by: 10) == true && p.position == 100 && !p.isPlaying)
        #expect(p.advance(by: 1) == false)
        p.seek(to: -5); #expect(p.position == 0)
        p.seek(to: 500); #expect(p.position == 100)
        p.toggle(); #expect(p.isPlaying)
    }

    @Test func pausedPlayersDontMove() {
        var p = AsciiPlayer(duration: 100, position: 10, isPlaying: false)
        _ = p.advance(by: 5)
        #expect(p.position == 10 && near(p.remaining, 90))
    }

    @Test func timesFormat() {
        #expect(AsciiPlayer.format(0) == "0:00" && AsciiPlayer.format(9.9) == "0:09" && AsciiPlayer.format(83) == "1:23" && AsciiPlayer.format(214) == "3:34" && AsciiPlayer.format(-4) == "0:00")
    }
}

@Suite("Model") struct ModelTests {
    @Test func startsCalmWithTheCoverInAscii() {
        var m = AsciiModel()
        _ = m.advance(to: 0)
        let cells = m.cells()
        #expect(cells.count == 48 * 48 && !m.isScrambling && cells.allSatisfy { !$0.scrambled })
        let glyphs = Set(cells.map(\.glyph))
        #expect(glyphs.isSubset(of: Set(AsciiRamp.ramp)) && glyphs.count >= 8)
        // The cover's dark hills at the bottom are mostly blank, the sun is dense.
        let bottom = cells.suffix(48 * 6), sun = cells[(14 * 48 + 24)]
        #expect(bottom.filter { $0.glyph == " " || $0.glyph == "." }.count > 200)
        #expect(sun.glyph != " ")
        #expect(cells.contains { $0.r != $0.g })
    }

    @Test func shimmerMovesTheArtOverTimeAndPausedCalmsIt() {
        var m = AsciiModel()
        _ = m.advance(to: 0)
        let a = text(m.cells())
        _ = run(&m, to: 1.5)
        let b = text(m.cells())
        #expect(a != b)
        // Paused: energy eases to the paused level.
        m.togglePlay(at: 1.5)
        _ = run(&m, from: 1.5, to: 4)
        #expect(near(m.energy, m.config.pausedEnergy))
        m.togglePlay(at: 4)
        _ = run(&m, from: 4, to: 6)
        #expect(near(m.energy, 1))
    }

    @Test func tapScramblesThenResolvesWithOneHaptic() {
        var m = AsciiModel()
        _ = m.advance(to: 0)
        let calm = text(m.cells())
        m.tap(at: Vec2(0.5, 0.5), time: 1)
        #expect(m.isScrambling)
        var events = run(&m, from: 1.0, to: 1 + AsciiScramble.hold - 0.05)
        #expect(events.contains(.scrambleStarted))
        // Mid-scramble: most cells are random glyphs.
        let mid = m.cells()
        #expect(mid.filter(\.scrambled).count > 48 * 48 * 9 / 10)
        #expect(Set(mid.map(\.glyph)).count > 14)
        #expect(Set(mid.map(\.glyph)).subtracting(Set(AsciiRamp.ramp)).count > 5)      // beyond the ramp
        events += run(&m, from: 1 + AsciiScramble.hold - 0.05, to: 1 + AsciiScramble.total + 0.2)
                #expect(events.filter { $0 == .resolved }.count == 1 && events.filter { $0 == .haptic }.count == 1 && m.resolveHaptics == 1)
        #expect(events.firstIndex(of: .resolved)! < events.firstIndex(of: .haptic)!)
        #expect(!m.isScrambling && m.cells().allSatisfy { !$0.scrambled })
        _ = calm
    }

    @Test func resolvedArtMatchesTheShimmerOnlyArt() {
        // After the scramble, the glyphs are the same as an untouched model at the same time.
        var a = AsciiModel(), b = AsciiModel()
        _ = a.advance(to: 0); _ = b.advance(to: 0)
        a.tap(time: 0)
        _ = run(&a, to: 3); _ = run(&b, to: 3)
        #expect(text(a.cells()) == text(b.cells()))
    }

    @Test func resolveWavesOutwardFromTheTapPoint() {
        var m = AsciiModel()
        _ = m.advance(to: 0)
        m.tap(at: Vec2(0.1, 0.1), time: 0)
        _ = run(&m, to: AsciiScramble.hold + 0.45)
        let n = 48, cells = m.cells()
        let near = (0..<4).flatMap { r in (0..<4).map { c in cells[r * n + c] } }
        let far = (44..<48).flatMap { r in (44..<48).map { c in cells[r * n + c] } }
        #expect(near.filter(\.scrambled).count == 0)
        #expect(far.filter(\.scrambled).count == far.count)
    }

    @Test func tapDuringScrambleRestartsWithNewGlyphs() {
        var m = AsciiModel()
        m.tap(time: 0)
        _ = run(&m, to: 0.5)
        let before = text(m.cells())
        let e0 = m.epoch
        m.tap(time: 0.5)
        #expect(m.epoch == e0 + 1 && m.scrambleStart == 0.5)
        let ev = m.advance(to: 0.5 + 0.2)
        #expect(ev.contains(.scrambleStarted) && !ev.contains(.resolved))
        #expect(text(m.cells()) != before)
        let all = run(&m, from: 0.7, to: 4)
        #expect(all.filter { $0 == .resolved }.count == 1)
    }

    @Test func hapticIsDebounced() {
        var m = AsciiModel()
        var ev: [AsciiEvent] = []
        m.tap(time: 0); ev += run(&m, to: 2)
        m.tap(time: 2); ev += run(&m, from: 2, to: 4)
        #expect(ev.filter { $0 == .haptic }.count == 2)           // 2 s apart: both play
        var r = AsciiModel(config: { var c = AsciiModel.Config(); c.reduceMotion = true; return c }())
        r.tap(time: 0); r.tap(time: 0.05)
        let e = r.advance(to: 0.06)
        #expect(e.filter { $0 == .haptic }.count == 1 && e.filter { $0 == .resolved }.count == 2)
    }

    @Test func reduceMotionHasNoShimmerAndResolvesInstantly() {
        var c = AsciiModel.Config(); c.reduceMotion = true
        var m = AsciiModel(config: c)
        _ = m.advance(to: 0)
        let a = text(m.cells())
        _ = run(&m, to: 2.3)
        #expect(text(m.cells()) == a && m.energy == 0)
        m.tap(time: 2.3)
        #expect(!m.isScrambling && m.cells().allSatisfy { !$0.scrambled })
        let ev = m.advance(to: 2.35)
        #expect(ev == [.resolved, .haptic])
        // Paused and reduced: nothing is running.
        m.togglePlay(at: 2.4)
        _ = m.advance(to: 2.5)
        #expect(m.isIdle)
    }

    @Test func densityResamplesTheGrid() {
        var m = AsciiModel()
        #expect(m.cols == 48)
        let changed = m.setColumns(72, at: 0)
        #expect(changed && m.cols == 72 && m.cells().count == 72 * 72 && m.grid.cols == 72)
        let same = m.setColumns(72, at: 0)
        #expect(!same)
        _ = m.setColumns(10, at: 0)
        #expect(m.cols == 24 && m.cells().count == 576)
        let up = m.stepDensity(up: true, at: 0)
        #expect(up && m.cols == 32)
        let ev = m.advance(to: 0)
        #expect(ev == [.densityChanged(72), .densityChanged(24), .densityChanged(32)])
        // Finer grids show more distinct detail than crunchy ones.
        let fine = AsciiGrid(source: AsciiCover.image(), cols: 72), crunchy = AsciiGrid(source: AsciiCover.image(), cols: 24)
        let row = { (g: AsciiGrid) in Int(Double(g.cols) * 0.45) }
        let edges = { (g: AsciiGrid) in (1..<g.cols).reduce(0.0) { s, i in s + abs(g.tones[row(g) * g.cols + i] - g.tones[row(g) * g.cols + i - 1]) } / Double(g.cols - 1) }
        #expect(edges(crunchy) > edges(fine))                                 // coarser cells jump more between neighbours
    }

    @Test func playbackAndSeekingAreTracked() {
        var m = AsciiModel(position: 100)
        _ = run(&m, to: 2)
        #expect(near(m.player.position, 102, 0.02))
        m.seek(to: 10, at: 2)
        #expect(m.player.position == 10)
        m.togglePlay(at: 2.1)
        let ev = m.advance(to: 3)
        #expect(ev == [.seeked, .playing(false)])
        #expect(m.announcement == "Paused" && m.announcementCount == 1)
        var end = AsciiModel(position: 213)
        let e2 = run(&end, to: 2)
        #expect(e2 == [.playing(false)] && !end.player.isPlaying)
    }

    @Test func announcementsAndAccessibilityText() {
        #expect(AsciiAnnouncement.text(for: .playing(true)) == "Playing")
        #expect(AsciiAnnouncement.text(for: .densityChanged(56)) == "Detail 56 columns, fine")
        #expect(AsciiAnnouncement.text(for: .resolved) == nil && AsciiAnnouncement.text(for: .haptic) == nil)
        var m = AsciiModel()
        #expect(m.accessibilityLabel == "Static Lullaby, Mira & the Quiet Arcades")
        #expect(m.accessibilityValue == "Playing, 1:23 of 3:34, ASCII cover at 48 columns, medium")
        _ = m.stepDensity(up: true, at: 0)
        #expect(m.announcement == "Detail 56 columns, fine" && m.announcementCount == 1)
        m.togglePlay(at: 0)
        #expect(m.accessibilityValue.hasPrefix("Paused"))
    }
}
