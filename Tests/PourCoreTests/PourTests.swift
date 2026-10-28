import Foundation
import Testing
@testable import PourCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

/// Steps the model at 60 Hz up to `t` and returns every event, in order.
/// Landing-related events only (drops the opening/closing markers a tap queues).
private func landings(_ e: [PourEvent]) -> [PourEvent] { e.filter { $0 != .opening && $0 != .closing } }

private func run(_ m: inout PourModel, to t: Double) -> [PourEvent] {
    var out: [PourEvent] = []
    var k = Int((m.time * 60).rounded())
    while Double(k + 1) / 60 <= t + 1e-9 {
        k += 1
        out += m.advance(to: Double(k) / 60)
    }
    return out
}

@Suite struct LayoutTests {
    @Test func restPositions() {
        #expect(PourLayout.pitch == 54)
        #expect(PourLayout.restCenter(0) == Vec2(110, 78))
        #expect(PourLayout.restCenter(3) == Vec2(110, 240))
        #expect(PourLayout.restBlob(3).bottom == 260)
        #expect(PourLayout.height(optionCount: 4) == 272)
        #expect(PourLayout.pillBlob == PourBlob(center: Vec2(110, 22), halfWidth: 80, radius: 22))
        // Neighbouring drops sit further apart at rest than the goo can bridge.
        #expect(PourLayout.restGap > PourLayout.breakGap)
    }

    @Test func neckNarrowsAndPinchesOff() {
        #expect(PourLayout.neckWidth(gap: -12) == PourLayout.maxNeck)
        #expect(PourLayout.neckWidth(gap: 0) == PourLayout.maxNeck)
        #expect(PourLayout.neckWidth(gap: PourLayout.breakGap) == 0)
        #expect(PourLayout.neckWidth(gap: 50) == 0)
        let ws = stride(from: -2.0, through: 12, by: 0.25).map { PourLayout.neckWidth(gap: $0) }
        #expect(zip(ws, ws.dropFirst()).allSatisfy { $0 >= $1 })
        let a = PourBlob(center: Vec2(110, 50), halfWidth: 70, radius: 20)
        func lower(_ gap: Double) -> PourBlob { PourBlob(center: Vec2(110, 70 + gap + 20), halfWidth: 70, radius: 20) }
        let touching = PourLayout.neck(upper: a, lower: lower(0))
        let stretched = PourLayout.neck(upper: a, lower: lower(7))
        #expect(touching?.width == 44 && touching?.waist == 44)
        #expect(stretched != nil && stretched!.waist < stretched!.width && stretched!.width < 20)
        #expect(PourLayout.neck(upper: a, lower: lower(10)) == nil)
        #expect(PourLayout.neck(upper: a, lower: lower(9.9)) == nil)     // under half a point wide
        let poly = touching!.polygon
        #expect(poly.count == 6 && near(poly[0].x + poly[5].x, 220) && near(poly[1].x + poly[4].x, 220))
        #expect(poly[0].y == 50 && poly[2].y == 90)
    }
}

@Suite struct TimelineTests {
    @Test func staggerAndTotal() {
        #expect(near(PourTimeline.total(optionCount: 4), 0.77) && near(PourTimeline.total(optionCount: 1), 0.5))
        #expect(PourTimeline.rawProgress(drop: 0, master: 0) == 0)
        #expect(PourTimeline.rawProgress(drop: 2, master: 0.18) == 0)
        #expect(near(PourTimeline.rawProgress(drop: 2, master: 0.43), 0.5))
        #expect(PourTimeline.rawProgress(drop: 3, master: 0.77) == 1)
    }

    @Test func dripEasingOvershootsAndLands() {
        #expect(near(PourTimeline.easeOutBack(0), 0, 1e-12) && near(PourTimeline.easeOutBack(1), 1))
        let xs = stride(from: 0.0, through: 1, by: 0.01).map(PourTimeline.easeOutBack)
        #expect(xs.max()! > 1.04 && xs.max()! < 1.08)
        let peak = xs.firstIndex(of: xs.max()!)!
        #expect(zip(xs[...peak], xs[...peak].dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func dropsStartInThePillAndLandAtRest() {
        for d in PourTimeline.drops(optionCount: 4, master: 0) {
            #expect(!d.isVisible && near(d.blob.center.x, 110) && near(d.blob.center.y, 22) && d.labelOpacity == 0)
            #expect(near(d.blob.radius, 20 * 0.55) && near(d.blob.halfWidth, 74 * 0.55))
        }
        let end = PourTimeline.drops(optionCount: 4, master: PourTimeline.total(optionCount: 4))
        for d in end {
            #expect(d.isVisible && d.labelOpacity == 1)
            #expect(near(d.blob.center.y, PourLayout.restCenter(d.index).y) && d.blob == PourLayout.restBlob(d.index))
        }
        let mid = PourTimeline.drops(optionCount: 4, master: 0.2)
        #expect(mid.map(\.isVisible) == [true, true, true, false])
        #expect(near(mid[0].raw, 0.4) && near(mid[1].raw, 0.22) && mid[1].blob.center.y > mid[2].blob.center.y)
        #expect(mid[0].blob.radius > mid[1].blob.radius && mid[1].blob.radius > mid[2].blob.radius)
    }

    @Test func labelsAppearAsDropsLand() {
        #expect(PourTimeline.drop(0, master: 0.29).labelOpacity == 0)        // raw 0.58 < 0.6
        let half = PourTimeline.drop(0, master: 0.4).labelOpacity            // raw 0.8
        #expect(half > 0.4 && half < 0.6)
        #expect(PourTimeline.drop(0, master: 0.5).labelOpacity == 1)
    }

    @Test func neckChainsDripsTopToBottom() {
        let n = 4, total = PourTimeline.total(optionCount: n)
        #expect(PourTimeline.necks(PourTimeline.drops(optionCount: n, master: 0)).isEmpty)
        #expect(PourTimeline.necks(PourTimeline.drops(optionCount: n, master: total)).isEmpty)
        // Early on drop 1 trails drop 0, so it bridges the pill to drop 0.
        let early = PourTimeline.necks(PourTimeline.drops(optionCount: n, master: 0.1))
        #expect(early.count == 2 && early[0].top == 22 && near(early[0].bottom, 31, 0.01) && near(early[1].bottom, 57.93, 0.01))
        // Mid-pour a drip is stretched thin between drops 1 and 2, then it breaks.
        let drip = PourTimeline.necks(PourTimeline.drops(optionCount: n, master: 0.4))
        #expect(drip.contains { $0.width < 5 && $0.waist < $0.width })
        let widths = stride(from: 0.3, through: 0.6, by: 0.01).map { u -> Double in
            let d = PourTimeline.drops(optionCount: n, master: u)
            return PourLayout.neck(upper: d[1].blob, lower: d[2].blob)?.width ?? 0
        }
        #expect(widths.first! == 44 && widths.last! == 0)
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 })
    }

    @Test func liftIsASineArc() {
        let t = PourTimeline.total(optionCount: 4)
        #expect(PourTimeline.lift(master: 0, optionCount: 4) == 0 && near(PourTimeline.lift(master: t, optionCount: 4), 0, 1e-12))
        #expect(near(PourTimeline.lift(master: t / 2, optionCount: 4), 1))
        #expect(near(PourTimeline.lift(master: t * 0.25, optionCount: 4), PourTimeline.lift(master: t * 0.75, optionCount: 4), 1e-12))
        #expect(near(PourTimeline.lift(master: t * 0.25, optionCount: 4), sin(.pi / 4)))
        #expect(near(PourLift.scale(1), 1.04) && PourLift.scale(0) == 1)
        #expect(PourLift.radius(1) == 16 && PourLift.radius(0) == 3)
        #expect(near(PourLift.opacity(1), 0.28) && near(PourLift.opacity(0), 0.10) && PourLift.offsetY(1) == 8)
    }

    @Test func labelFadeIsEased() {
        #expect(PourLabelFade.progress(elapsed: 0) == 0 && PourLabelFade.progress(elapsed: 0.28) == 1)
        #expect(near(PourLabelFade.progress(elapsed: 0.14), 0.5) && PourLabelFade.progress(elapsed: 5) == 1)
        #expect(near(PourLabelFade.progress(elapsed: 0.075, duration: 0.15), 0.5))
    }
}

@Suite struct ModelTests {
    @Test func tapOpensAndLands() {
        var m = PourModel()
        #expect(m.state == .closed && !m.acceptsPick && m.isIdle && m.lift == 0)
        m.tapPill(at: 0)
        let e0 = m.advance(to: 0)
        #expect(e0 == [.opening] && m.state == .opening && m.acceptsPick)
        let e1 = run(&m, to: 0.3)
        #expect(e1.isEmpty && m.lift > 0.5 && m.state == .opening)
        let e2 = run(&m, to: 1)
        #expect(e2 == [.landed(open: true), .haptic] && m.state == .open && m.landings == 1)
        #expect(near(m.master, 0.77) && m.progress == 1 && m.chevronAngle == 180 && m.lift < 1e-9)
        #expect(m.isIdle && m.isExpanded)
    }

    @Test func pickingPoursBackAndCrossfades() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 1)
        let ok = m.pick(2, at: 1)
        #expect(ok)
        let e = m.advance(to: 1)
        #expect(e == [.selected(2), .labelChanged(from: 0, to: 2), .closing])
        #expect(m.state == .closing && m.selected == 2 && !m.acceptsPick)
        #expect(m.label.from == 0 && m.label.to == 2 && m.label.fromOpacity == 1 && m.label.toOpacity == 0)
        _ = m.advance(to: 1.14)
        #expect(near(m.label.toOpacity, 0.5, 1e-6) && near(m.label.fromOpacity, 0.5, 1e-6))
        let land = run(&m, to: 2)
        #expect(land == [.landed(open: false), .haptic] && m.state == .closed && m.master == 0)
        #expect(m.label.toOpacity == 1 && m.label.from == 2 && m.isIdle && m.landings == 2)
        #expect(m.drops.allSatisfy { !$0.isVisible })
    }

    @Test func pickingTheSameOptionSkipsTheCrossfade() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 1)
        let ok = m.pick(0, at: 1)
        #expect(ok)
        let e = m.advance(to: 1)
        #expect(e == [.selected(0), .closing] && !m.isLabelFading)
    }

    @Test func picksOutsideTheOpenMenuAreIgnored() {
        var m = PourModel()
        let closedPick = m.pick(1, at: 0)
        let closedEvents = m.advance(to: 0)
        #expect(!closedPick && closedEvents.isEmpty && m.selected == 0)
        m.tapPill(at: 0)
        _ = run(&m, to: 1)
        let bad = m.pick(9, at: 1), negative = m.pick(-1, at: 1)
        #expect(!bad && !negative && m.state == .open)
        let first = m.pick(3, at: 1)
        let second = m.pick(1, at: 1.05)                       // already pouring back up
        #expect(first && !second && m.selected == 3)
    }

    @Test func tapWhileAnimatingReversesWithoutAJump() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 0.3)
        let before = m.master
        m.tapPill(at: 0.3)
        let e = m.advance(to: 0.3)
        #expect(e == [.closing] && m.state == .closing && near(m.master, before))
        _ = run(&m, to: 0.4)
        #expect(m.master < before && near(m.master, before - 0.1, 1e-9))
        m.tapPill(at: 0.4)                                    // changed our mind again
        let again = m.advance(to: 0.4)
        #expect(again == [.opening] && m.state == .opening)
        let tail = run(&m, to: 2)
        #expect(tail == [.landed(open: true), .haptic] && m.state == .open)
        // Tapping while it's open closes; tapping mid-close reopens.
        m.tapPill(at: 2)
        _ = run(&m, to: 2.2)
        #expect(m.state == .closing)
        m.tapPill(at: 2.2)
        #expect(m.state == .opening)
    }

    @Test func pickWhileOpeningTakesTheCurrentDropsBack() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 0.25)
        let mid = m.master
        let ok = m.pick(1, at: 0.25)
        #expect(ok && m.state == .closing && near(m.master, mid))
        let tail = run(&m, to: 2)
        #expect(tail.contains(.selected(1)) && tail.last == .haptic && tail.contains(.landed(open: false)) && !tail.contains(.landed(open: true)))
    }

    @Test func hapticsAreDebounced() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 0.05)
        m.tapPill(at: 0.05)                                   // back up: lands closed at ~0.1
        let a = run(&m, to: 0.1)
        #expect(landings(a) == [.landed(open: false), .haptic] && m.landings == 1)
        m.tapPill(at: 0.1)
        _ = run(&m, to: 0.15)
        m.tapPill(at: 0.15)
        let b = run(&m, to: 0.3)
        #expect(landings(b) == [.landed(open: false)] && m.landings == 1)        // within 0.15 s of the last haptic
        m.tapPill(at: 0.5)
        _ = run(&m, to: 0.55)
        m.tapPill(at: 0.55)
        let c = run(&m, to: 0.7)
        #expect(landings(c) == [.landed(open: false), .haptic] && m.landings == 2)
    }

    @Test func labelCrossfadeMidFade() {
        var m = PourModel()
        m.tapPill(at: 0)
        _ = run(&m, to: 1)
        _ = m.pick(1, at: 1)
        _ = run(&m, to: 1.05)                                 // a little into the fade (< half)
        m.tapPill(at: 1.05)
        let ok = m.pick(2, at: 1.05)
        #expect(ok && m.label.from == 0 && m.label.to == 2)   // still fading out the first option
        var n = PourModel()
        n.tapPill(at: 0)
        _ = run(&n, to: 1)
        _ = n.pick(1, at: 1)
        _ = run(&n, to: 1.18)                                 // well past half
        n.tapPill(at: 1.18)
        let ok2 = n.pick(2, at: 1.18)
        #expect(ok2 && n.label.from == 1 && n.label.to == 2)
    }

    @Test func reduceMotionIsAPlainFade() {
        var c = PourModel.Config()
        c.reduceMotion = true
        var m = PourModel(config: c)
        m.tapPill(at: 0)
        _ = run(&m, to: 0.1)
        #expect(m.necks.isEmpty && m.lift == 0 && near(m.menuOpacity, 0.5, 1e-6))
        #expect(m.drops.map(\.blob) == (0..<4).map(PourLayout.restBlob))   // no travelling, just fading
        let e = run(&m, to: 0.25)
        #expect(e == [.landed(open: true), .haptic] && m.state == .open && m.menuOpacity == 1)
        let ok = m.pick(3, at: 0.25)
        #expect(ok)
        _ = m.advance(to: 0.325)
        #expect(near(m.label.toOpacity, 0.5, 1e-6))           // 0.15 s crossfade
        let end = run(&m, to: 1)
        #expect(end.contains(.landed(open: false)) && m.isIdle && m.menuOpacity == 0)
    }

    @Test func worksForOtherOptionCounts() {
        var m = PourModel(options: ["A", "B", "C"], selected: 2)
        #expect(near(m.total, 0.68) && m.selected == 2 && m.drops.count == 3)
        m.tapPill(at: 0)
        let e = run(&m, to: 1)
        #expect(e == [.opening, .landed(open: true), .haptic])
        let clamped = PourModel(options: ["A"], selected: 5)
        #expect(clamped.selected == 0 && near(clamped.total, 0.5))
    }
}

@Suite struct CatalogTests {
    @Test func sortsByTheChosenOption() {
        let items = PourCatalog.items
        #expect(PourCatalog.sorted(items, by: "Newest").map(\.age) == items.map(\.age).sorted())
        #expect(PourCatalog.sorted(items, by: "Oldest").map(\.age) == items.map(\.age).sorted(by: >))
        #expect(PourCatalog.sorted(items, by: "Popular").map(\.likes) == items.map(\.likes).sorted(by: >))
        let az = PourCatalog.sorted(items, by: "A to Z").map(\.title)
        #expect(az == az.sorted() && Set(az) == Set(items.map(\.title)))
        #expect(PourCatalog.sorted(items, by: "Nope").map(\.id) == items.map(\.id))
        #expect(Set(items.map(\.id)).count == items.count)
    }
}
