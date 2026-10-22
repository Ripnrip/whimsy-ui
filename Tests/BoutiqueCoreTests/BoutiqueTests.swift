import Testing
@testable import BoutiqueCore

private let layout = BoutiqueLayout(width: 393, height: 852)

@Suite struct FigureSpecTests {
    @Test func crowdIsDeterministicAndVaried() {
        let a = FigureSpec.crowd(count: 42, seed: 7), b = FigureSpec.crowd(count: 42, seed: 7)
        #expect(a == b)
        #expect(a != FigureSpec.crowd(count: 42, seed: 8))
        #expect(Set(a.map(\.color)).count >= 8)
        #expect(Set(a.map(\.garment)).count == FigureSpec.Garment.allCases.count)
        #expect(a.map(\.id) == Array(0..<42))
    }

    @Test func neighboursDifferAndAccentsContrast() {
        let crowd = FigureSpec.crowd(count: 200, seed: 0xB0_7140)
        for (p, q) in zip(crowd, crowd.dropFirst()) { #expect(p.color != q.color) }
        for f in crowd {
            #expect(f.accent != f.color)
            #expect(FigureSpec.palette.indices.contains(f.color) && FigureSpec.palette.indices.contains(f.accent))
            #expect(FigureSpec.skinTones.indices.contains(f.skin) && (0...3).contains(f.hairStyle))
            #expect(f.price >= 120 && f.price <= 480 && f.price % 5 == 0)
            #expect(f.height >= 0.92 && f.height <= 1.06)
        }
        #expect(crowd[0].name.hasSuffix(crowd[0].garment.name))
    }

    @Test func emptyCrowd() {
        #expect(FigureSpec.crowd(count: 0, seed: 1).isEmpty)
        #expect(FigureSpec.crowd(count: -3, seed: 1).isEmpty)
    }
}

@Suite struct LayoutTests {
    @Test func restScatterClearsTheWordAndEachOther() {
        let rest = layout.restPlacements()
        #expect(rest.count == 6)
        let size = layout.figureSize(scale: BoutiqueLayout.restScale)
        let word = layout.wordRect.insetBy(-BoutiqueLayout.wordMargin)
        for r in rest {
            let box = BoxRect(center: r.center, width: size.width, height: size.height)
            #expect(layout.safeBounds.contains(box))
            #expect(!box.intersects(word))
            #expect(abs(r.tilt) <= 8)
        }
        for i in rest.indices { for j in rest.indices where j > i {
            #expect(rest[i].center.distance(to: rest[j].center) >= BoutiqueLayout.restSpacing)
        } }
        // Alternates above and below the word.
        for (i, r) in rest.enumerated() { #expect((r.center.y < layout.wordRect.center.y) == (i % 2 == 0)) }
        #expect(layout.restPlacements().map(\.center) == rest.map(\.center))
    }

    @Test func burstFillsTheScreenOnAJitteredGrid() {
        let burst = layout.burstPlacements()
        #expect(burst.count == 42)
        #expect(layout.rows == 7)
        let size = layout.figureSize(scale: layout.burstScale), c = layout.cell
        #expect(size.width <= c.width && size.height <= c.height)
        for (i, p) in burst.enumerated() {
            let box = BoxRect(center: p.center, width: size.width, height: size.height)
            #expect(layout.safeBounds.insetBy(-0.001).contains(box), "figure \(i) escapes")
            // Stays inside its own cell, so figures never overlap.
            let row = i / BoutiqueLayout.columns, col = i % BoutiqueLayout.columns
            let cellBox = BoxRect(x: layout.safeBounds.minX + Double(col) * c.width, y: layout.safeBounds.minY + Double(row) * c.height, width: c.width, height: c.height)
            #expect(cellBox.insetBy(-0.001).contains(box))
            #expect(abs(p.tilt) <= 4)
        }
        // It covers the screen: figures reach near every edge.
        let xs = burst.map(\.center.x), ys = burst.map(\.center.y)
        #expect(xs.min()! < 50 && xs.max()! > 343 && ys.min()! < 140 && ys.max()! > 720)
    }

    @Test func staggerRipplesOutwardFromTheTouch() {
        let burst = layout.burstPlacements().map(\.center)
        let origin = burst[20]
        let plain = layout.staggerDelays(from: origin, positions: burst, spread: 0.45, jitter: 0)
        #expect(plain[20] == 0)
        #expect(abs(plain.max()! - 0.45) < 1e-12)
        for i in burst.indices { for j in burst.indices where burst[i].distance(to: origin) < burst[j].distance(to: origin) {
            #expect(plain[i] <= plain[j])
        } }
        let noisy = layout.staggerDelays(from: origin, positions: burst, spread: 0.45)
        for (n, p) in zip(noisy, plain) { #expect(n >= p && n <= p + BoutiqueLayout.delayJitter) }
        #expect(noisy == layout.staggerDelays(from: origin, positions: burst, spread: 0.45))
    }

    @Test func exitCarriesFiguresAwayAndOffScreen() {
        let burst = layout.burstPlacements().map(\.center)
        let sel = burst[14]
        let size = layout.figureSize(scale: layout.burstScale)
        for (i, p) in burst.enumerated() where i != 14 {
            let o = layout.exitOffset(for: p, awayFrom: sel)
            #expect(o.dot(p - sel) > 0)
            #expect(abs(o.normalized.cross((p - sel).normalized)) < 1e-9)
            let end = BoxRect(center: p + o, width: size.width, height: size.height)
            #expect(!end.intersects(BoxRect(x: 0, y: 0, width: 393, height: 852)))
        }
        #expect(layout.exitOffset(for: sel, awayFrom: sel).normalized == Vec2(0, 1))
    }

    @Test func springProgressMatchesTheSwiftUISpring() {
        #expect(BoutiqueLayout.springProgress(0) == 0)
        #expect(BoutiqueLayout.springProgress(-1) == 0)
        let samples = stride(from: 0.0, through: 1.2, by: 0.01).map { BoutiqueLayout.springProgress($0) }
        #expect(samples.max()! > 1.02)          // a visible bounce
        #expect(abs(BoutiqueLayout.springProgress(1.5) - 1) < 0.01)
        #expect(BoutiqueLayout.springProgress(.infinity) == 1)
    }
}

@Suite struct ModelTests {
    @Test func phaseMachine() {
        var m = BoutiqueModel(layout: layout)
        #expect(m.phase == .rest)
        do { let changed = m.send(.close); #expect(!changed) }
        do { let changed = m.send(.focusSettled); #expect(!changed) }
        do { let changed = m.send(.tapBackground, at: Vec2(100, 600)); #expect(changed) }
        #expect(m.phase == .burst && m.origin == Vec2(100, 600))
        do { let changed = m.send(.tapBackground); #expect(!changed) }
        do { let changed = m.send(.tapFigure(99)); #expect(!changed) }
        do { let changed = m.send(.tapFigure(9)); #expect(changed) }
        #expect(m.phase == .focusing(9) && m.phase.selected == 9)
        do { let changed = m.send(.tapFigure(3)); #expect(!changed) }
        do { let changed = m.send(.focusSettled); #expect(changed) }
        #expect(m.phase == .detail(9))
        do { let changed = m.send(.close); #expect(changed) }
        #expect(m.phase == .burst && m.origin == m.burst[9].center)
        var s = BoutiqueModel(layout: layout)
        do { let changed = s.send(.scroll); #expect(changed) }
        #expect(s.origin == Vec2(393 / 2, 852))
    }

    @Test func placementsPerPhase() {
        let m = BoutiqueModel(layout: layout)
        for i in 0..<42 {
            let r = m.placement(of: i, in: .rest)
            #expect(r.opacity == (i < 6 ? 1 : 0))
            let b = m.placement(of: i, in: .burst)
            #expect(b.opacity == 1 && b.center == m.burst[i].center && b.scale == layout.burstScale)
            let f = m.placement(of: i, in: .focusing(5))
            if i == 5 {
                #expect(f.opacity == 1 && f.tilt == 0 && f.center == b.center)
            } else {
                #expect(f.opacity == 0)
                #expect((f.center - b.center).dot(b.center - m.burst[5].center) > 0)
            }
            #expect(m.placement(of: i, in: .detail(5)) == f)
        }
    }

    @Test func delaysFollowThePhase() {
        var m = BoutiqueModel(layout: layout)
        #expect(m.delays().allSatisfy { $0 == 0 })
        m.send(.tapBackground, at: m.burst[0].center)
        let d = m.delays()
        #expect(d.count == 42 && d[0] <= BoutiqueLayout.delayJitter)
        #expect(d[41] > d[1])
        #expect(m.delays(reduceMotion: true).allSatisfy { $0 == 0 })
        m.send(.tapFigure(20))
        let e = m.delays()
        #expect(e[20] == 0)
        #expect(e.max()! <= BoutiqueLayout.exitSpread + 0.02)
    }
}
