import Foundation
import Testing
@testable import OctoCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

/// Steps the model at 60 Hz up to `t` and returns every event, in order.
private func run(_ m: inout OctoModel, to t: Double) -> [OctoEvent] {
    var out: [OctoEvent] = []
    var k = Int((m.time * 60).rounded())
    while Double(k + 1) / 60 <= t + 1e-9 {
        k += 1
        out += m.advance(to: Double(k) / 60)
    }
    return out
}

/// A model with row `i` ticked at time 0 and advanced to `t`.
private func ticked(_ i: Int = 0, to t: Double, config: OctoModel.Config = OctoModel.Config()) -> OctoModel {
    var m = OctoModel(config: config)
    m.tap(i, at: 0)
    _ = run(&m, to: t)
    return m
}

@Suite struct TimingTests {
    @Test func phasesFollowTheClock() {
        let t = OctoTiming.full
        #expect(t.phase(at: 0) == .idle && t.phase(at: -1) == .idle)
        #expect(t.phase(at: 0.1) == .check && t.phase(at: 0.25) == .swell && t.phase(at: 0.69) == .swell)
        #expect(t.phase(at: 0.7) == .grab && t.phase(at: 1.0) == .pull && t.phase(at: 1.29) == .pull)
        #expect(t.phase(at: 1.3) == .collapse && t.phase(at: 1.79) == .collapse && t.phase(at: 1.8) == .gone)
        #expect(t.total == 1.8 && t.commit == 0.7 && t.collapseStart < t.pullEnd)    // the collapse overlaps the pull
        #expect(OctoTiming.reduced.total == 0.7 && OctoTiming.reduced.isReduced)
    }

    @Test func progressHandlesZeroLengthSpans() {
        #expect(OctoTiming.progress(0.5, from: 0, to: 1) == 0.5)
        #expect(OctoTiming.progress(-1, from: 0, to: 1) == 0 && OctoTiming.progress(3, from: 0, to: 1) == 1)
        #expect(OctoTiming.progress(0.19, from: 0.2, to: 0.2) == 0 && OctoTiming.progress(0.2, from: 0.2, to: 0.2) == 1)
    }
}

@Suite struct FrameTests {
    @Test func phasesDriveTheirOwnProgress() {
        var m = OctoModel()
        #expect(m.frame(0).check == 0 && m.frame(0).blob == nil && m.frame(0).opacity == 1 && m.frame(0).scaleY == 1)
        m.tap(0, at: 0)
        _ = run(&m, to: 0.25)
        let f1 = m.frame(0)
        #expect(near(f1.check, 1, 1e-9) && f1.swell == 0 && f1.blob == nil)
        _ = run(&m, to: 0.475)                                  // halfway through the swell
        let f2 = m.frame(0)
        #expect(f2.swell > 0.8 && f2.swell < 1 && f2.blob != nil && f2.grab == 0)
        _ = run(&m, to: 0.85)
        let f3 = m.frame(0)
        #expect(near(f3.swell, 1, 1e-9) && near(f3.grab, 0.5, 0.2) && f3.pull == 0 && f3.offsetY == 0)
        _ = run(&m, to: 1.2)
        #expect(m.frame(0).phase == .pull && m.frame(0).offsetY > 20 && m.frame(0).pull > 0.3)
    }

    @Test func squashAndStretchPreserveVolume() {
        var m = OctoModel()
        m.tap(0, at: 0)
        var minSY = 2.0, maxSY = 0.0
        for k in 1...120 {
            _ = m.advance(to: Double(k) / 60)
            let f = m.frame(0)
            #expect(near(f.scaleX * f.scaleY, 1, 1e-12))
            minSY = min(minSY, f.scaleY); maxSY = max(maxSY, f.scaleY)
        }
        #expect(minSY < 0.9 && minSY > 0.85)                     // gathers (squashes) as it grabs
        #expect(maxSY > 1.25 && maxSY < 1.45)                    // then stretches as it is pulled
        let end = m.frame(0)
        #expect(near(end.scaleY, 1, 1e-6) && end.phase == .gone)
    }

    @Test func pullIsSpringy() {
        var m = OctoModel()
        m.tap(0, at: 0)
        var offsets: [Double] = []
        for k in 1...108 {
            _ = m.advance(to: Double(k) / 60)
            if m.clock(0) >= 1.0 { offsets.append(m.frame(0).offsetY) }
        }
        #expect(offsets.max()! > OctoLayout.pullDistance * 1.1)   // overshoots the rest point
        #expect(offsets.first! < 5)                               // and starts gently
    }

    @Test func collapseSpringsAndLandsExactly() {
        let t = OctoTiming.full
        #expect(OctoModel.collapse(clock: 1.0, timing: t) == 0 && OctoModel.collapse(clock: 1.3, timing: t) == 0)
        #expect(OctoModel.collapse(clock: 1.8, timing: t) == 1 && OctoModel.collapse(clock: 5, timing: t) == 1)
        let cs = stride(from: 1.3, through: 1.8, by: 0.01).map { OctoModel.collapse(clock: $0, timing: t) }
        #expect(cs.max()! > 1.04 && cs.max()! < 1.2)
        let r = OctoTiming.reduced
        let rs = stride(from: 0.4, through: 0.71, by: 0.01).map { OctoModel.collapse(clock: $0, timing: r) }
        #expect(rs.max()! == 1 && zip(rs, rs.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func rowFadesDuringThePull() {
        let m1 = ticked(to: 0.99), m2 = ticked(to: 1.4), m3 = ticked(to: 1.6)
        #expect(m1.frame(0).opacity == 1 && m2.frame(0).opacity < 0.9 && m2.frame(0).opacity > 0.1 && m3.frame(0).opacity == 0)
        #expect(!m3.frame(0).showsInk)
    }
}

@Suite struct LayoutTests {
    @Test func slotsAndTops() {
        let m = OctoModel()
        let f = m.frames
        #expect(f.map(\.top) == [0, 64, 128, 192, 256] && f.allSatisfy { $0.slotHeight == 64 })
        #expect(m.listHeight == 5 * 64 - 8)
    }

    @Test func rowsBelowRiseAsARowCollapses() {
        var m = OctoModel()
        m.tap(1, at: 0)
        _ = run(&m, to: 1.2)
        #expect(m.frames[2].top == 128)                                    // not collapsing yet
        var tops: [Double] = []
        for k in 73...108 { _ = m.advance(to: Double(k) / 60); tops.append(m.frames[2].top) }
        #expect(tops.first! > 120 && tops.min()! < 64 - 2)                 // overshoots past the final spot, then settles
        #expect(near(tops.last!, 64) && near(m.frames[3].top, 128) && near(m.frames[4].top, 192))
        #expect(m.frames[0].top == 0 && m.frames[1].top == 64 && near(m.frames[1].slotHeight, 0))
        #expect(near(m.listHeight, 4 * 64 - 8))
    }

    @Test func collapsedRowsHaveNoHeight() {
        var m = OctoModel()
        m.tap(1, at: 0); m.tap(3, at: 0)
        _ = run(&m, to: 3)
        #expect(m.goneCount == 2 && m.frames.map(\.heightScale) == [1, 0, 1, 0, 1])
        #expect(near(m.listHeight, 3 * 64 - 8) && near(m.frames[4].top, 128))
    }
}

@Suite struct InkTests {
    @Test func blobSwellsUpFromBelow() {
        #expect(OctoInk.blob(swell: 0) == nil)
        let a = OctoInk.blob(swell: 0.2)!, b = OctoInk.blob(swell: 0.6)!, c = OctoInk.blob(swell: 1)!
        #expect(a.rx < b.rx && b.rx < c.rx && a.ry < b.ry && b.ry < c.ry)
        #expect(a.center.y > b.center.y && b.center.y > c.center.y && a.center.y > OctoLayout.rowHeight)
        #expect(near(c.rx, 204) && near(c.center.y, 56 * 0.62) && near(c.center.x, 170))
    }

    @Test func falloffIsRadialAndMonotone() {
        #expect(OctoInk.falloff(0) == 1 && OctoInk.falloff(1) == 0 && OctoInk.falloff(2) == 0)
        let fs = stride(from: 0.0, through: 1, by: 0.05).map(OctoInk.falloff)
        #expect(zip(fs, fs.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func halftoneDotsFollowTheGradient() {
        #expect(OctoInk.dots(blob: nil).isEmpty)
        let blob = OctoInk.blob(swell: 1)!
        let dots = OctoInk.dots(blob: blob)
        #expect(dots.count > 300 && dots.count < 1500)
        #expect(dots.allSatisfy { $0.r >= OctoInk.minDot && $0.r <= OctoInk.maxDot })
        for d in dots {
            let nx = (d.x - blob.center.x) / blob.rx, ny = (d.y - blob.center.y) / blob.ry
            #expect(nx * nx + ny * ny < 1)
        }
        // Bigger dots near the middle than near the edge.
        let mid = dots.filter { abs($0.x - blob.center.x) < 20 && abs($0.y - blob.center.y) < 10 }.map(\.r).max()!
        let edge = dots.filter { abs($0.x - blob.center.x) > 150 }.map(\.r).max()!
        #expect(mid > 3 && edge < mid * 0.6)
        // Hex-ish lattice: odd rows are shifted half a cell.
        let ys = Set(dots.map { ($0.y * 1000).rounded() / 1000 }).sorted()
        #expect(ys.count > 5)
    }

    @Test func dotCountGrowsWithTheSwell() {
        let counts = [0.1, 0.3, 0.6, 1.0].map { OctoInk.dots(blob: OctoInk.blob(swell: $0)).count }
        #expect(counts[0] < counts[1] && counts[1] < counts[2] && counts[2] < counts[3])
    }

    @Test func latticeStaysPutAsTheBlobGrows() {
        func keys(_ s: Double) -> Set<String> { Set(OctoInk.dots(blob: OctoInk.blob(swell: s)).map { String(format: "%.6f,%.6f", $0.x, $0.y) }) }
        #expect(keys(0.5).isSubset(of: keys(1.0)))
    }

    @Test func tentacleCurlsOverTheRowAndTapers() {
        #expect(OctoInk.tentacle(grab: 0).isEmpty)
        let counts = [0.1, 0.3, 0.6, 1.0].map { OctoInk.tentacle(grab: $0).count }
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 } && counts.last! > 120)
        let full = OctoInk.tentacle(grab: 1)
        #expect(full[1].x > 170 && full[1].y > 28)                            // starts bottom right
        #expect(full.map(\.y).min()! < 0 && full.map(\.x).min()! < 25 && full.map(\.x).max()! > 340)   // wraps over the top and down the left
        let widths = stride(from: 0.0, through: 1, by: 0.05).map(OctoInk.tentacleThickness)
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 > $1 } && widths.first! > 15 && widths.last! < 2)
        #expect(OctoInk.tentacle(grab: 0.5).count < full.count)
    }
}

@Suite struct StateTests {
    @Test func tickRunsToGoneWithEventsAndHaptics() {
        var m = OctoModel()
        let ok = m.tap(2, at: 0)
        #expect(ok && m.isChecked(2) && !m.isGone(2))
        var e = m.advance(to: 0.1)
        #expect(m.phase(2) == .check)
        e += run(&m, to: 3)
        #expect(e == [.ticked(2), .grabbed(2), .haptic(.grab), .gone(2), .haptic(.gone)])
        #expect(m.isGone(2) && m.goneCount == 1 && m.isIdle && !m.isBusy)
    }

    @Test func tickWhileAnimatingUndoesBeforeTheGrab() {
        var m = OctoModel()
        m.tap(0, at: 0)
        _ = run(&m, to: 0.5)
        #expect(!m.isCommitted(0))
        let undo = m.tap(0, at: 0.5)
        #expect(undo && !m.isChecked(0))
        let e = run(&m, to: 1)
        #expect(e == [.unticked(0), .undone(0)])
        #expect(m.clock(0) == 0 && m.phase(0) == .idle && m.isIdle)
        // Rolling back runs twice as fast as it went forward: 0.5 s of clock takes 0.25 s.
        var n = OctoModel()
        n.tap(0, at: 0); _ = run(&n, to: 0.5); n.tap(0, at: 0.5)
        _ = run(&n, to: 0.5 + 0.1)
        #expect(near(n.clock(0), 0.3, 0.02))
    }

    @Test func tappingAgainWhileRollingBackResumes() {
        var m = OctoModel()
        m.tap(0, at: 0)
        _ = run(&m, to: 0.5)
        m.tap(0, at: 0.5)
        _ = run(&m, to: 0.6)
        let before = m.clock(0)
        let again = m.tap(0, at: 0.6)
        #expect(again && m.isChecked(0) && near(m.clock(0), before))
        let e = run(&m, to: 3)
        #expect(e.contains(.gone(0)) && !e.contains(.undone(0)) && m.isGone(0))
    }

    @Test func committedAndGoneRowsIgnoreTaps() {
        var m = OctoModel()
        m.tap(1, at: 0)
        _ = run(&m, to: 0.9)                                   // the ink has grabbed the row
        #expect(m.isCommitted(1))
        let before = m
        let ignored = m.tap(1, at: 0.9)
        #expect(!ignored && m.advance(to: 0.9).isEmpty && m.clock(1) == before.clock(1))
        _ = run(&m, to: 3)
        let afterGone = m.tap(1, at: 3)
        let outOfRange = m.tap(9, at: 3)
        #expect(!afterGone && !outOfRange && m.isGone(1))
    }

    @Test func tapBetweenFramesDoesntLoseEvents() {
        var m = OctoModel()
        m.tap(0, at: 0)
        _ = m.advance(to: 0)
        m.tap(1, at: 0.8)                                       // the grab of row 0 happened before this tap
        let e = m.advance(to: 0.8)
        #expect(e == [.grabbed(0), .haptic(.grab), .ticked(1)])
    }

    @Test func completeAllSweepsRowsInOrder() {
        var m = OctoModel()
        m.tap(1, at: 0)
        _ = run(&m, to: 0.9)                                    // row 1 is already committed
        let n = m.completeAll(at: 0.9)
        #expect(n == 4 && !m.canCompleteAll)
        let e = run(&m, to: 6)
        let order = e.compactMap { ev -> Int? in if case .ticked(let i) = ev { return i } else { return nil } }
        #expect(order == [0, 2, 3, 4])
        #expect(e.first == .sweepStarted(4) || e.contains(.sweepStarted(4)))
        let gone = e.compactMap { ev -> Int? in if case .gone(let i) = ev { return i } else { return nil } }
        #expect(gone == [1, 0, 2, 3, 4] && e.contains(.allDone) && e.firstIndex(of: .allDone)! > e.lastIndex(of: .gone(4))!)
        #expect(m.isAllDone && m.listHeight == 0)
        // Starts are `sweepStagger` apart.
        var s = OctoModel()
        s.completeAll(at: 0)
        var started: [Int: Double] = [:]
        for k in 1...120 { for ev in s.advance(to: Double(k) / 60) { if case .ticked(let i) = ev { started[i] = Double(k) / 60 } } }
        let gaps = (1..<5).map { started[$0]! - started[$0 - 1]! }
        #expect(gaps.allSatisfy { abs($0 - 0.28) < 0.02 } && started[0]! < 0.05)
    }

    @Test func completeAllWithNothingLeftDoesNothing() {
        var m = OctoModel(titles: ["a"])
        m.tap(0, at: 0)
        _ = run(&m, to: 3)
        let n = m.completeAll(at: 3)
        #expect(n == 0 && m.advance(to: 3).isEmpty)
    }

    @Test func completeAllPicksUpRollingBackRowsAndTapStartsEarly() {
        var m = OctoModel()
        m.tap(0, at: 0)
        _ = run(&m, to: 0.4)
        m.tap(0, at: 0.4)                                       // rolling back
        let n = m.completeAll(at: 0.4)
        #expect(n == 5)
        let early = m.tap(3, at: 0.5)                           // a tap on a row still waiting starts it now
        #expect(early && m.isChecked(3))
        let none = m.completeAll(at: 0.5)
        #expect(none == 0)                                      // everything else is already scheduled
        _ = run(&m, to: 8)
        #expect(m.isAllDone)
    }

    @Test func hapticsAreDebouncedPerKind() {
        var c = OctoModel.Config()
        c.sweepStagger = 0.05
        var m = OctoModel(config: c)
        m.completeAll(at: 0)
        let e = run(&m, to: 6)
        let grabs = e.filter { $0 == .haptic(.grab) }.count, goneHaptics = e.filter { $0 == .haptic(.gone) }.count
        let grabbed = e.filter { if case .grabbed = $0 { return true } else { return false } }.count
        #expect(grabbed == 5 && grabs < 5 && grabs >= 2 && goneHaptics < 5 && goneHaptics >= 2)
        // With the default stagger every landing gets its haptic.
        var d = OctoModel()
        d.completeAll(at: 0)
        let e2 = run(&d, to: 8)
        #expect(e2.filter { $0 == .haptic(.grab) }.count == 5 && e2.filter { $0 == .haptic(.gone) }.count == 5)
    }

    @Test func resetBringsRowsBack() {
        var m = OctoModel()
        m.tap(0, at: 0); m.tap(3, at: 0)
        _ = run(&m, to: 3)
        m.tap(1, at: 3)
        _ = run(&m, to: 3.2)                                    // row 1 is mid-flight
        let ok = m.reset(at: 3.2)
        let e = m.advance(to: 3.2)
        #expect(ok && e == [.reset] && m.clock(1) == 0 && m.goneCount == 0)
        #expect(m.frame(1).opacity == 1 && m.frame(1).heightScale == 1)          // snapped back
        #expect(m.frame(0).opacity == 0 && m.frame(0).slotHeight == 0)           // gone rows start collapsed …
        _ = run(&m, to: 3.4)
        let mid = m.frame(0)
        #expect(mid.restore > 0.5 && mid.restore < 1 && mid.slotHeight > 0 && mid.slotHeight < 64 && m.isBusy)
        _ = run(&m, to: 4)
        #expect(m.frame(0).slotHeight == 64 && m.frames.map(\.top) == [0, 64, 128, 192, 256] && m.isIdle)
        let nothing = m.reset(at: 4)
        #expect(!nothing)
    }

    @Test func reduceMotionFadesAndCollapsesWithoutInk() {
        var c = OctoModel.Config()
        c.reduceMotion = true
        var m = OctoModel(config: c)
        m.tap(0, at: 0)
        var sawInk = false, maxOffset = 0.0, minSY = 1.0, maxSY = 1.0
        var events: [OctoEvent] = []
        for k in 1...60 {
            events += m.advance(to: Double(k) / 60)
            let f = m.frame(0)
            sawInk = sawInk || f.showsInk || f.blob != nil
            maxOffset = max(maxOffset, abs(f.offsetY)); minSY = min(minSY, f.scaleY); maxSY = max(maxSY, f.scaleY)
        }
        #expect(!sawInk && maxOffset == 0 && minSY == 1 && maxSY == 1)
        #expect(m.isGone(0) && m.timing(0) == .reduced && m.clock(0) == 0.7)
        #expect(events == [.ticked(0), .grabbed(0), .haptic(.grab), .gone(0), .haptic(.gone)])
        let mid = ticked(to: 0.3, config: c)
        #expect(mid.frame(0).opacity > 0.2 && mid.frame(0).opacity < 0.9 && mid.frame(0).check == 1)
        #expect(mid.frame(0).collapse == 0)
    }

    @Test func countersTrackHapticsAndAnnouncements() {
        var m = OctoModel()
        #expect(m.grabHaptics == 0 && m.goneHaptics == 0 && m.announcementCount == 0 && m.announcement == nil && !m.canReset)
        m.tap(0, at: 0)
        #expect(m.announcement == "Completed Water the ferns" && m.announcementCount == 1 && m.canReset)
        _ = run(&m, to: 3)
        #expect(m.grabHaptics == 1 && m.goneHaptics == 1 && m.announcementCount == 1)
        m.reset(at: 3)
        #expect(m.announcement == "List reset" && m.announcementCount == 2)
        _ = run(&m, to: 4)
        #expect(!m.canReset)
    }

    @Test func announcements() {
        let t = OctoCatalog.titles
        #expect(OctoAnnouncement.text(for: .ticked(0), titles: t) == "Completed Water the ferns")
        #expect(OctoAnnouncement.text(for: .unticked(2), titles: t) == "Fold the laundry not completed")
        #expect(OctoAnnouncement.text(for: .sweepStarted(3), titles: t) == "Completing 3 tasks")
        #expect(OctoAnnouncement.text(for: .sweepStarted(1), titles: t) == "Completing 1 task")
        #expect(OctoAnnouncement.text(for: .allDone, titles: t) == "All tasks completed")
        #expect(OctoAnnouncement.text(for: .reset, titles: t) == "List reset")
        #expect(OctoAnnouncement.text(for: .gone(0), titles: t) == nil && OctoAnnouncement.text(for: .haptic(.grab), titles: t) == nil)
        #expect(t.count == 5 && Set(t).count == 5)
    }
}
