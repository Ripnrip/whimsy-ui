import Testing
import Foundation
@testable import FontCollectionCore

private let catalog = FontCatalog.standard

// MARK: - Catalog

@Suite("Catalog")
struct CatalogTests {
    @Test func sixteenUniqueSpecimensCoveringEveryCategory() {
        #expect(catalog.count == 16)
        #expect(Set(catalog.ids).count == 16)
        #expect(Set(catalog.specimens.map(\.category)) == Set(FontCategory.allCases))
        #expect(catalog.availableFilters == FontFilter.chips)
    }

    @Test func allFourSystemDesignsAndOnlyBuiltInFamilies() {
        let designs = catalog.specimens.compactMap { s -> SystemFontDesign? in
            if case .system(let d) = s.source { return d } else { return nil }
        }
        #expect(Set(designs) == Set(SystemFontDesign.allCases))
        // Families that ship with both iOS 17 and macOS 14 (no bundled files).
        let builtIn: Set<String> = ["Avenir Next", "Didot", "Futura", "Georgia", "Baskerville", "Gill Sans",
                                    "American Typewriter", "Menlo", "Snell Roundhand", "Copperplate", "Optima",
                                    "Rockwell", "Bodoni 72", "Marker Felt", "Chalkboard SE"]
        for s in catalog.specimens {
            if let family = s.source.familyName { #expect(builtIn.contains(family), "\(family)") }
        }
    }

    @Test func everySpecimenHasSampleWeightsAndSensibleFallback() {
        for s in catalog.specimens {
            #expect(!s.sample.isEmpty && s.sample.count <= 20)
            #expect(!s.note.isEmpty)
            #expect(!s.weights.isEmpty && s.weights == s.weights.sorted())
            #expect(s.weights.contains(s.displayWeight))
        }
        #expect(catalog.specimen(id: "menlo")?.fallbackDesign == .monospaced)
        #expect(catalog.specimen(id: "didot")?.fallbackDesign == .serif)
        #expect(catalog.specimen(id: "chalkboard")?.fallbackDesign == .rounded)
        #expect(catalog.specimen(id: "american-typewriter")?.fallbackDesign == .monospaced)
    }

    @Test func initNormalisesWeightsAndDisplayWeight() {
        let s = FontSpecimen(id: "x", name: "X", source: .named(family: "X"), category: .sans, sample: "x",
                             weights: [.bold, .light, .bold], displayWeight: .regular)
        #expect(s.weights == [.light, .bold])
        #expect(s.displayWeight == .light) // 400 is 100 from 300 and 300 from 700
        let empty = FontSpecimen(id: "y", name: "Y", source: .system(.default), category: .sans, sample: "y", weights: [])
        #expect(empty.weights == [.regular] && empty.displayWeight == .regular)
        #expect(s.nearestWeight(to: .black) == .bold)
    }

    @Test func duplicateIDsAreDropped() {
        let a = FontSpecimen(id: "a", name: "A", source: .system(.default), category: .sans, sample: "a")
        let a2 = FontSpecimen(id: "a", name: "A2", source: .system(.serif), category: .serif, sample: "b")
        let c = FontCatalog([a, a2])
        #expect(c.count == 1 && c.specimens[0].name == "A")
        #expect(c.index(of: "a") == 0 && c.index(of: "zz") == nil)
    }

    @Test func filterByCategoryKeepsCatalogOrder() {
        let serif = catalog.visible(filter: .category(.serif)).map(\.id)
        #expect(serif == ["new-york", "georgia", "baskerville", "rockwell"])
        #expect(catalog.visible(filter: .category(.script)).map(\.id) == ["snell-roundhand"])
        #expect(catalog.visible().count == 16)
        let total = FontCategory.allCases.map { catalog.count(for: .category($0)) }.reduce(0, +)
        #expect(total == catalog.count(for: .all))
    }

    @Test func sortByNameAndCategory() {
        let byName = catalog.visible(sort: .name).map(\.name)
        #expect(byName.first == "American Typewriter" && byName.last == "Snell Roundhand")
        #expect(byName == byName.sorted { $0.lowercased() < $1.lowercased() })
        let byCat = catalog.visible(sort: .category)
        let idx = byCat.map(\.category.sortIndex)
        #expect(idx == idx.sorted())
        // Stable within a category.
        #expect(byCat.filter { $0.category == .mono }.map(\.id) == ["sf-mono", "menlo", "american-typewriter"])
    }

    @Test func searchIsCaseAndDiacriticInsensitive() {
        #expect(catalog.visible(query: "DIDOT").map(\.id) == ["didot"])
        #expect(catalog.visible(query: "  ").count == 16)
        #expect(catalog.visible(query: "mono").map(\.id) == ["sf-mono", "menlo", "american-typewriter"])
        let cafe = FontSpecimen(id: "c", name: "Café", source: .system(.default), category: .sans, sample: "c")
        #expect(cafe.matches(query: "cafe") && cafe.matches(query: "CAFÉ") && !cafe.matches(query: "tea"))
        #expect(catalog.visible(filter: .category(.serif), query: "geo").map(\.id) == ["georgia"])
    }

    @Test func chipTitlesAndWeightNames() {
        #expect(FontFilter.chips.map(\.title) == ["All", "Serif", "Sans", "Rounded", "Mono", "Display", "Script"])
        #expect(FontWeightStep.allCases.map(\.cssWeight) == [100, 200, 300, 400, 500, 600, 700, 800, 900])
        #expect(FontWeightStep.semibold.title == "Semibold" && FontWeightStep.light < .bold)
    }
}

// MARK: - Flip board

@Suite("Flip board")
struct FlipBoardTests {
    let board = FlipBoardSchedule(fontCount: 16, startFont: 0, target: 13, columns: 9, seed: 42)

    @Test func endsOnTargetWithNoRepeatsAndTargetOnlyAtTheEnd() {
        #expect(board.flips.count == 14)
        #expect(board.flips.last?.toFont == 13 && board.flips.last?.isFinal == true)
        #expect(board.flips.dropLast().allSatisfy { $0.toFont != 13 && !$0.isFinal })
        for f in board.flips { #expect(f.fromFont != f.toFont) }
        // Each flap starts from the previous flap's font.
        #expect(board.flips[0].fromFont == 0)
        for k in 1..<board.flips.count { #expect(board.flips[k].fromFont == board.flips[k - 1].toFont) }
    }

    @Test func gapsEaseInFromFastToSlow() {
        let gaps = zip(board.flips.dropFirst(), board.flips).map { $0.time - $1.time }
        #expect(abs(gaps.first! - 0.05) < 1e-12)
        for k in 1..<gaps.count { #expect(gaps[k] >= gaps[k - 1] - 1e-12) }
        #expect(abs(FlipBoardSchedule.interval(13, count: 14) - 0.26) < 1e-12)
        #expect(board.flips.first?.time == 0)
        // Total run is about 1.4 s for the default tuning.
        #expect(board.settleTime > 1.0 && board.settleTime < 1.8)
    }

    @Test func foldsNeverOverlapTheNextFlap() {
        for (a, b) in zip(board.flips, board.flips.dropFirst()) { #expect(a.time + a.foldDuration < b.time) }
        #expect(abs(board.flips.last!.foldDuration - 0.09 * 1.8) < 1e-12)
    }

    @Test(arguments: [1, 2, 3, 99, 0xDEAD_BEEF] as [UInt64])
    func sameSeedSameRunDifferentSeedDifferentRun(seed: UInt64) {
        let a = FlipBoardSchedule(fontCount: 16, target: 5, columns: 4, seed: seed)
        let b = FlipBoardSchedule(fontCount: 16, target: 5, columns: 4, seed: seed)
        let c = FlipBoardSchedule(fontCount: 16, target: 5, columns: 4, seed: seed &+ 1)
        #expect(a == b)
        #expect(a.flips.map(\.toFont) != c.flips.map(\.toFont))
    }

    @Test func cellsWaveLeftToRightAndSettleInOrder() {
        // Mid-way through flap 3 of column 0, column 8 hasn't reached it yet.
        let t = board.flips[3].time + 0.02
        let c0 = board.cell(column: 0, at: t), c8 = board.cell(column: 8, at: t)
        #expect(c0.toFont == board.flips[3].toFont)
        #expect(c8.toFont != c0.toFont || c8.progress < c0.progress)
        // Column k settles stagger·k after column 0.
        let s0 = board.settleTime
        #expect(board.cell(column: 0, at: s0).isSettled)
        #expect(!board.cell(column: 1, at: s0).isSettled)
        #expect(board.cell(column: 1, at: s0 + 0.028 + 1e-9).isSettled)
        #expect(abs(board.duration - (s0 + 8 * 0.028)) < 1e-12)
        #expect(board.isSettled(at: board.duration) && !board.isSettled(at: board.duration - 0.001))
        #expect(board.cells(at: 99).allSatisfy { $0.isSettled && $0.visibleFont == 13 })
    }

    @Test func cellBeforeStartAndFlapAngle() {
        let c = board.cell(column: 3, at: -1)
        #expect(c.fromFont == 0 && c.toFont == 0 && c.progress == 1 && !c.isSettled)
        var s = FlipCellState(fromFont: 1, toFont: 2, progress: 0, isSettled: false)
        #expect(s.flapAngle == 0 && s.visibleFont == 1)
        s.progress = 0.25; #expect(abs(s.flapAngle + 45) < 1e-12)
        s.progress = 0.5; #expect(abs(s.flapAngle - 90) < 1e-12 && s.visibleFont == 2)
        s.progress = 1; #expect(s.flapAngle == 0)
        // Out-of-range columns clamp.
        #expect(board.cell(column: 99, at: 0.5) == board.cell(column: 8, at: 0.5))
    }

    @Test func hapticsTickEveryFlapGetStrongerAndSettleOnce() {
        let all = board.hapticEvents(after: -1, through: 10)
        let ticks = all.compactMap { e -> Double? in if case .flipTick(let i) = e.event { return i } else { return nil } }
        #expect(ticks.count == 13)
        #expect(abs(ticks.first! - 0.3) < 1e-12 && abs(ticks.last! - 0.8) < 1e-12)
        #expect(ticks == ticks.sorted())
        #expect(all.filter { $0.event == .settle }.count == 1)
        #expect(all.last?.event == .settle && abs(all.last!.time - board.settleTime) < 1e-12)
        // Windows partition the run: no event counted twice or lost.
        var n = 0, t = -1.0
        while t < 3 { n += board.hapticEvents(after: t, through: t + 1.0 / 60).count; t += 1.0 / 60 }
        #expect(n == all.count)
        #expect(board.hapticEvents(after: 1, through: 1).isEmpty)
    }

    @Test func reduceMotionIsOneInstantChange() {
        let r = FlipBoardSchedule(fontCount: 16, startFont: 2, target: 9, columns: 5, seed: 1, reduceMotion: true)
        #expect(r.flips.count == 1 && r.duration == 0)
        #expect(r.cells(at: 0).allSatisfy { $0.isSettled && $0.visibleFont == 9 })
        #expect(r.hapticEvents(after: -0.01, through: 0.1).map(\.event) == [.settle])
        #expect(r.hapticEvents(after: 0, through: 0.1).isEmpty)
    }

    @Test func degenerateInputsClamp() {
        let one = FlipBoardSchedule(fontCount: 0, startFont: 5, target: 7, columns: 0, seed: 3)
        #expect(one.fontCount == 1 && one.columns == 1 && one.target == 0)
        #expect(one.flips.allSatisfy { $0.toFont == 0 })
        let two = FlipBoardSchedule(fontCount: 2, startFont: 0, target: 1, columns: 2, seed: 3)
        #expect(two.flips.last?.toFont == 1)
        var t = FlipBoardTuning(); t.flips = 1
        let single = FlipBoardSchedule(fontCount: 8, target: 3, columns: 3, seed: 1, tuning: t)
        #expect(single.flips.count == 1 && single.flips[0].toFont == 3)
        #expect(FlipBoardSchedule.interval(0, count: 1) == 0.05)
    }
}

// MARK: - Layout & regroup

@Suite("Regroup")
struct RegroupTests {
    let layout = SpecimenGridLayout(width: 393)
    var all: [String] { catalog.visible().map(\.id) }
    var serif: [String] { catalog.visible(filter: .category(.serif)).map(\.id) }

    @Test func gridSlotsAreRowMajorAndFitTheWidth() {
        #expect(abs(layout.cardWidth - (393 - 32 - 14) / 2) < 1e-12)
        let a = layout.center(0), b = layout.center(1), c = layout.center(2)
        #expect(a.y == b.y && b.x > a.x && c.x == a.x && c.y > a.y)
        #expect(abs(c.y - a.y - (196 + 14)) < 1e-12)
        #expect(abs(layout.center(1).x + layout.cardWidth / 2 - (393 - 16)) < 1e-9)
        #expect(layout.contentHeight(count: 16) == 32 + 8 * 196 + 7 * 14)
        #expect(layout.contentHeight(count: 3) == layout.contentHeight(count: 4))
        #expect(layout.contentHeight(count: 0) == 32)
        let tiny = SpecimenGridLayout(columns: 0, width: -5)
        #expect(tiny.columns == 1 && tiny.cardWidth == 0)
    }

    @Test func springRisesOvershootsAndSettles() {
        let t = RegroupTuning()
        #expect(t.spring(0) == 0 && t.spring(-1) == 0)
        let samples = stride(from: 0.0, through: 3.0, by: 0.005).map(t.spring)
        #expect(samples.max()! > 1.0 && samples.max()! < 1.08) // ζ 0.72 → ~4% overshoot
        #expect(abs(t.spring(3) - 1) < 1e-4)
        let lt = t.landingTime
        #expect(t.spring(lt) >= 0.985 && t.spring(lt - 0.001) < 0.985)
        var crit = RegroupTuning(); crit.dampingRatio = 1.4
        let cs = stride(from: 0.0, through: 3.0, by: 0.01).map(crit.spring)
        #expect(cs.max()! <= 1 + 1e-12 && cs == cs.sorted())
    }

    @Test func filterPlanKindsAndSlots() {
        let plan = RegroupPlan(from: all, to: serif, layout: layout, seed: 7)
        #expect(plan.flights.count == 16)
        let moves = plan.flights.filter { $0.kind == .move }
        #expect(moves.map(\.id) == serif)
        #expect(plan.flights.filter { $0.kind == .leave }.count == 12)
        #expect(plan.flights.filter { $0.kind == .enter }.isEmpty)
        for (i, id) in serif.enumerated() {
            let f = plan.flight(id: id)!
            #expect(f.slot == i && f.to == layout.center(i))
            #expect(f.from == layout.center(all.firstIndex(of: id)!))
            #expect(abs(f.delay - Double(i) * 0.045) < 1e-12)
        }
        // And back again: the serif cards fly back to their catalog slots, the others enter.
        let back = RegroupPlan(from: serif, to: all, layout: layout, seed: 7)
        #expect(back.flights.filter { $0.kind == .enter }.count == 12)
        #expect(back.flights.allSatisfy { $0.kind != .leave })
    }

    @Test func posesStartAtOldSlotsHopTiltAndEndAtNewSlots() {
        let plan = RegroupPlan(from: all, to: serif, layout: layout, seed: 7)
        let georgia = plan.flight(id: "georgia")!
        #expect(georgia.from != georgia.to && georgia.hop > 0 && georgia.hop <= 36)
        let p0 = plan.pose(georgia, at: 0)
        #expect(p0.center == georgia.from && p0.rotation == 0 && p0.opacity == 1)
        // Mid-flight it is above the straight line and tilted.
        let mid = plan.pose(georgia, at: georgia.delay + 0.12)
        let p = plan.tuning.spring(0.12)
        let straight = Vec2.lerp(georgia.from, georgia.to, p)
        #expect(mid.center.y < straight.y - 1)
        #expect(abs(mid.rotation) > 0 || georgia.tilt == 0)
        #expect(mid.zIndex > 1)
        let end = plan.pose(georgia, at: plan.duration)
        #expect(end.center.distance(to: georgia.to) < 0.5 && abs(end.rotation) < 0.05 && abs(end.scale - 1) < 0.01)
        // Sans cards already sit in slots 0…2: no hop, no tilt, no movement.
        let sans = RegroupPlan(from: all, to: catalog.visible(filter: .category(.sans)).map(\.id), layout: layout, seed: 7)
        let pro = sans.flight(id: "sf-pro")!
        #expect(pro.from == pro.to && pro.hop == 0 && pro.tilt == 0)
        #expect(sans.pose(pro, at: 0.2).center == pro.to)
        #expect(sans.landings.isEmpty)
    }

    @Test func leaversShrinkAndFadeEnterersGrowIn() {
        let plan = RegroupPlan(from: all, to: serif, layout: layout, seed: 7)
        let didot = plan.flight(id: "didot")!
        #expect(plan.pose(didot, at: 0).opacity == 1)
        let half = plan.pose(didot, at: 0.12)
        #expect(half.opacity < 1 && half.scale < 1 && half.zIndex == 0)
        #expect(plan.pose(didot, at: 0.24).opacity == 0)
        let back = RegroupPlan(from: serif, to: all, layout: layout, seed: 7)
        let e = back.flight(id: "didot")!
        let e0 = back.pose(e, at: 0)
        #expect(e0.opacity == 0 && abs(e0.scale - 0.6) < 1e-12 && e0.center == e.to + Vec2(0, 42))
        let e1 = back.pose(e, at: back.duration)
        #expect(e1.opacity == 1 && e1.center.distance(to: e.to) < 0.5)
    }

    @Test func landingsOncePerTravellingCardInSlotOrder() {
        let plan = RegroupPlan(from: all, to: serif, layout: layout, seed: 7)
        let l = plan.landings
        #expect(l.map(\.id) == serif)
        #expect(l.allSatisfy { $0.time < plan.duration })
        let lt = plan.tuning.landingTime
        #expect(abs(l[0].time - lt) < 1e-12 && abs(l[1].time - (0.045 + lt)) < 1e-12)
        var count = 0, t = -0.01
        while t < 2 { count += plan.landingEvents(after: t, through: t + 1.0 / 60).count; t += 1.0 / 60 }
        #expect(count == 4)
    }

    @Test func seededTiltsAreDeterministic() {
        let a = RegroupPlan(from: all, to: serif, layout: layout, seed: 1)
        let b = RegroupPlan(from: all, to: serif, layout: layout, seed: 1)
        let c = RegroupPlan(from: all, to: serif, layout: layout, seed: 2)
        #expect(a == b)
        #expect(a.flights.map(\.tilt) != c.flights.map(\.tilt))
        #expect(a.flights.allSatisfy { abs($0.tilt) <= 9 })
    }

    @Test func reduceMotionCrossfadesInPlace() {
        let plan = RegroupPlan(from: all, to: serif, layout: layout, seed: 7, reduceMotion: true)
        let g = plan.flight(id: "georgia")!
        #expect(plan.pose(g, at: 0).center == g.to)
        #expect(plan.pose(plan.flight(id: "didot")!, at: 0.12).opacity == 0.5)
        #expect(plan.landings.isEmpty && plan.duration == 0.24)
    }

    @Test func emptyAndIdenticalPlans() {
        let same = RegroupPlan(from: all, to: all, layout: layout, seed: 3)
        #expect(same.landings.isEmpty && same.flights.allSatisfy { $0.from == $0.to })
        let none = RegroupPlan(from: [], to: [], layout: layout, seed: 3)
        #expect(none.flights.isEmpty && none.duration == 0 && none.isSettled(at: 0))
        let dup = RegroupPlan(from: ["a", "a"], to: ["b", "b"], layout: layout, seed: 3)
        #expect(dup.flights.map(\.id) == ["b", "a"])
    }
}

// MARK: - Detail

@Suite("Detail")
struct DetailTests {
    let futura = catalog.specimen(id: "futura")!
    let avenir = catalog.specimen(id: "avenir-next")!

    @Test func defaultsToPangramDisplayWeightAndClampsSize() {
        var d = SpecimenDetailState(specimen: avenir)
        #expect(d.displayText == SpecimenDetailState.defaultSample && d.size == 44)
        #expect(d.weight == .medium && d.weightStops == 6)
        d.setSize(500); #expect(d.size == 120)
        d.setSize(-3); #expect(d.size == 18)
        d.setSize(.nan); #expect(d.size == 44)
    }

    @Test func sampleTextIsSanitised() {
        var d = SpecimenDetailState(specimen: futura)
        d.setSampleText("Hello\nthere\r\nfriend")
        #expect(d.sampleText == "Hello there friend")
        d.setSampleText(String(repeating: "a", count: 200))
        #expect(d.sampleText.count == 80)
        d.setSampleText("")
        #expect(d.displayText == SpecimenDetailState.defaultSample)
    }

    @Test func weightSliderSnapsToRealWeightsAndTicksOnChange() {
        var d = SpecimenDetailState(specimen: avenir) // [UL, R, M, SB, B, H]
        #expect(abs(d.weightPosition - 0.4) < 1e-12)
        #expect(d.setWeightPosition(0.42) == nil) // still medium
        do { let e = d.setWeightPosition(0.55); #expect(e == .weightStep && d.weight == .semibold) }
        do { let e = d.setWeightPosition(1); #expect(e == .weightStep && d.weight == .heavy) }
        do { let e = d.setWeightPosition(0); #expect(e == .weightStep && d.weight == .ultraLight) }
        #expect(d.weightSteps == 3)
        do { let e = d.setWeightPosition(.infinity); #expect(e == nil) }
        d.setWeightPosition(0.33); d.snapWeight()
        #expect(abs(d.weightPosition - 0.4) < 1e-12 && d.weight == .medium)
    }

    @Test func positionAndWeightRoundTrip() {
        for s in catalog.specimens {
            for w in s.weights {
                let p = SpecimenDetailState.position(of: w, in: s.weights)
                #expect(SpecimenDetailState.weight(at: p, in: s.weights) == w)
            }
        }
        #expect(SpecimenDetailState.position(of: .black, in: [.regular]) == 0)
        #expect(SpecimenDetailState.weight(at: 0.7, in: []) == .regular)
        #expect(SpecimenDetailState(specimen: futura).weight == .medium)
    }

    @Test func glyphStripHasTheWholeAlphabet() {
        #expect(GlyphStrip.uppercase.count == 26 && GlyphStrip.lowercase.count == 26 && GlyphStrip.digits.count == 10)
        #expect(GlyphStrip.all.count == 62 + GlyphStrip.punctuation.count)
        #expect(GlyphStrip.all.allSatisfy { $0.count == 1 })
        #expect(GlyphStrip.all.first == "A" && GlyphStrip.lowercase.last == "z")
    }
}

// MARK: - Haptics & model

@Suite("Haptics")
struct HapticTests {
    @Test func gateCollapsesFlurriesButAlwaysSettles() {
        var g = HapticGate(minInterval: 0.04)
        do { let ok = g.admit(.landing, at: 0); #expect(ok) }
        do { let ok = g.admit(.landing, at: 0.02); #expect(!ok) }
        do { let ok = g.admit(.settle, at: 0.03); #expect(ok) }
        do { let ok = g.admit(.chip, at: 0.05); #expect(!ok) }
        do { let ok = g.admit(.chip, at: 0.08); #expect(ok) }
        do { let ok = g.admit(.chip, at: .nan); #expect(!ok) }
        g.reset()
        do { let ok = g.admit(.weightStep, at: 0.081); #expect(ok) }
    }

    @Test func intensitiesAreClamped() {
        #expect(FontHapticEvent.flipTick(intensity: 3).intensity == 1)
        #expect(FontHapticEvent.flipTick(intensity: -1).intensity == 0)
        #expect(FontHapticEvent.settle.intensity == 1)
    }
}

@Suite("Model")
struct ModelTests {
    private func run(_ m: inout FontCollectionModel, seconds: Double) -> [FontHapticEvent] {
        var out: [FontHapticEvent] = []
        for _ in 0..<Int((seconds * 60).rounded()) { out += m.step(1.0 / 60) }
        return out
    }

    @Test func boardRunsOnLaunchAndSettlesWithHaptics() {
        var m = FontCollectionModel()
        #expect(!m.isHeadlineSettled && m.headlineCells.count == 9)
        let events = run(&m, seconds: 2.5)
        #expect(m.isHeadlineSettled && m.isSettled)
        #expect(m.headlineCells.allSatisfy { $0.visibleFont == m.flipTarget })
        #expect(m.settleCount == 1 && events.filter { $0 == .settle }.count == 1)
        #expect(m.tickCount == 13) // 50 ms minimum gap ≥ the 40 ms gate
    }

    @Test func sameSeedSameRun() {
        var a = FontCollectionModel(seed: 9), b = FontCollectionModel(seed: 9)
        #expect(run(&a, seconds: 1) == run(&b, seconds: 1))
        #expect(a == b)
        #expect(FontCollectionModel(seed: 9).flipBoard != FontCollectionModel(seed: 10).flipBoard)
    }

    @Test func chipRegroupsCardsAndLands() {
        var m = FontCollectionModel()
        _ = run(&m, seconds: 2.5)
        m.setFilter(.category(.mono))
        #expect(m.visibleIDs == ["sf-mono", "menlo", "american-typewriter"])
        #expect(!m.isRegroupSettled)
        #expect(m.cardPoses.count == 16) // leavers still fading
        let events = run(&m, seconds: 2)
        #expect(events.first == .chip)
        #expect(m.landingCount == 3)
        #expect(m.isSettled && m.cardPoses.count == 3)
        #expect(m.cardPoses["menlo"]!.center.distance(to: m.layout.center(1)) < 0.5)
        #expect(m.contentHeight == m.layout.contentHeight(count: 3))
        m.setFilter(.category(.mono)) // no-op
        #expect(m.isRegroupSettled)
    }

    @Test func sortReordersWithoutChipHaptic() {
        var m = FontCollectionModel()
        _ = run(&m, seconds: 2.5)
        m.setSort(.name)
        #expect(m.visibleIDs.first == "american-typewriter")
        let events = run(&m, seconds: 2)
        #expect(!events.contains(.chip) && events.contains(.landing))
    }

    @Test func shuffleHeadlinePicksAnotherFont() {
        var m = FontCollectionModel()
        _ = run(&m, seconds: 2.5)
        for _ in 0..<20 {
            let before = m.flipTarget
            m.shuffleHeadline()
            #expect(m.flipTarget != before)
            #expect(m.flipBoard.startFont == before)
            _ = run(&m, seconds: 2.5)
        }
        m.shuffleHeadline(to: 3)
        _ = run(&m, seconds: 2.5)
        #expect(m.headlineCells.allSatisfy { $0.visibleFont == 3 })
    }

    @Test func detailOpensEditsAndTicksOnWeightSteps() {
        var m = FontCollectionModel()
        _ = run(&m, seconds: 2.5)
        m.open("nope"); #expect(m.detail == nil)
        m.open("baskerville")
        #expect(m.detail?.specimen.name == "Baskerville")
        m.updateDetail { $0.setWeightPosition(1) }
        #expect(run(&m, seconds: 0.1) == [.weightStep])
        m.updateDetail { $0.setWeightPosition(0.98) }
        #expect(run(&m, seconds: 0.1).isEmpty)
        m.updateDetail { $0.setSampleText("Hamburgefonstiv") }
        #expect(m.detail?.displayText == "Hamburgefonstiv")
        m.close(); #expect(m.detail == nil)
        m.updateDetail { $0.setSize(90) }
        #expect(m.detail == nil)
    }

    @Test func reduceMotionSettlesImmediately() {
        var m = FontCollectionModel(reduceMotion: true)
        let first = m.step(1.0 / 60)
        #expect(m.isHeadlineSettled && first.contains(.settle))
        m.setFilter(.category(.display))
        _ = run(&m, seconds: 0.3)
        #expect(m.isSettled && m.landingCount == 0)
    }

    @Test func resizeRelaysWithoutAnimation() {
        var m = FontCollectionModel(width: 393)
        _ = run(&m, seconds: 2.5)
        m.resize(width: 600)
        #expect(m.isRegroupSettled)
        #expect(m.cardPoses["sf-pro"]!.center == SpecimenGridLayout(width: 600).center(0))
        #expect(m.step(.nan).isEmpty && m.step(0).isEmpty)
    }
}
