import Foundation
import Testing
@testable import GlassPourCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

private func pump(_ model: inout GlassPourModel, seconds: Double) -> [GlassPourEvent] {
    var events: [GlassPourEvent] = []
    var left = seconds
    while left > 1e-9 {
        let h = min(left, 1.0 / 60)
        events.append(contentsOf: model.step(h))
        left -= h
    }
    return events
}

@Suite struct ModelTests {
    @Test func defaultsAndClamps() {
        let model = GlassPourModel()
        #expect(model.items.map(\.title) == ["Share", "Duplicate", "Rename", "Delete"])
        #expect(model.items.map(\.symbol) == ["square.and.arrow.up", "plus.square.on.square", "pencil", "trash"])
        #expect(model.items.map(\.destructive) == [false, false, false, true])
        #expect(GlassPourModel(items: []).items.map(\.id) == GlassDropItem.defaults.map(\.id))
        let many = (0..<8).map { GlassDropItem(title: "Row \($0)", symbol: "circle", id: "r\($0)") }
        #expect(GlassPourModel(items: many).count == GlassPourTuning.maxRows)
        #expect(model.phase == .closed && !model.isExpanded && !model.animates && !model.usesGoo)
        #expect(model.dropAccessibilityLabel == "Menu")
        #expect(model.dropAccessibilityValue == "Closed")
        #expect(model.dropAccessibilityHint == "Opens the menu")
        #expect(GlassPourTuning.openedAnnouncement == "Menu opened")
        #expect(GlassPourTuning.closedAnnouncement == "Menu closed")
    }

    @Test func aShortPressDoesNotOpen() {
        var model = GlassPourModel()
        #expect(model.pressDrop().isEmpty && model.phase == .arming && model.animates)
        let midway = pump(&model, seconds: 0.16)
        #expect(midway.isEmpty && model.phase == .arming)
        #expect(near(model.dropScale, 1 + 0.07 * (model.phaseTime / GlassPourTuning.longPress), 1e-9))
        #expect(model.dropScale > 1.03 && model.dropScale < 1.04)
        let released = model.releaseDrop()
        #expect(released == [.pulsed] && model.phase == .closed && model.dropScale == 1)
        #expect(model.rows.allSatisfy { $0.travel == 0 && !$0.isVisible })
        #expect(model.pressOutside().isEmpty && model.selectRow(3).isEmpty && model.selectRow(-1).isEmpty)
    }

    @Test func holdingPastTheThresholdPoursOpen() {
        var model = GlassPourModel()
        model.pressDrop()
        let arming = pump(&model, seconds: 0.30)
        #expect(arming.isEmpty && model.phase == .arming)
        let opened = pump(&model, seconds: 2.0 / 60)
        #expect(opened == [.opening] && model.phase == .opening && model.usesGoo)
        let early = pump(&model, seconds: 0.24)
        #expect(early.isEmpty)
        #expect(model.rows[0].travel > model.rows[1].travel)
        #expect(model.rows[1].travel > model.rows[2].travel)
        #expect(model.rows[2].travel > model.rows[3].travel)
        #expect(model.rows[3].travel > 0)
        #expect(!model.necks.isEmpty)
        var peak = 0.0
        var wobble = 0.0
        var rest: [GlassPourEvent] = []
        for _ in 0..<84 {
            rest.append(contentsOf: model.step(1.0 / 60))
            for row in model.rows {
                peak = max(peak, row.travel)
                wobble = max(wobble, abs(row.wobble))
            }
        }
        #expect(rest.contains(.opened) && rest.contains(.haptic) && model.phase == .open)
        #expect(!model.usesGoo && model.necks.isEmpty && model.isExpanded)
        #expect(peak > 1.04 && peak < 1.12)
        for row in model.rows {
            #expect(near(row.travel, 1, 2e-3))
            #expect(near(row.center.y, GlassPourLayout.restCenter(row.index).y, 0.4))
            #expect(row.opacity == 1 && row.pinch > 0.99 && row.isInteractive)
        }
        #expect(model.rows[0].wobble == 0 && model.rows[1].wobble == 0 && model.rows[2].wobble == 0)
        #expect(wobble > 0.08 && wobble < 0.16)
        _ = pump(&model, seconds: 1.6)
        #expect(abs(model.rows[3].wobble) < 0.01 && !model.animates)
        #expect(model.dropAccessibilityValue == "Open")
        #expect(model.dropAccessibilityHint == "Closes the menu")
    }

    @Test func tappingOutsideSucksTheRowsBack() {
        var model = GlassPourModel()
        model.activateDrop()
        _ = pump(&model, seconds: 1.5)
        #expect(model.phase == .open)
        #expect(model.pressOutside() == [.closing] && model.phase == .closing && model.usesGoo)
        #expect(model.selectRow(0).isEmpty && model.pressDrop().isEmpty)
        let events = pump(&model, seconds: 1.6)
        #expect(events.contains(.closed) && model.phase == .closed && model.fade == 0)
        #expect(model.rows.allSatisfy { $0.travel == 0 && $0.wobble == 0 && !$0.isVisible })
        #expect(model.necks.isEmpty)
    }

    @Test func choosingDeleteClosesAndOnlyDeleteWobbles() {
        var model = GlassPourModel()
        model.activateDrop()
        _ = pump(&model, seconds: 1.5)
        #expect(model.hitTest(GlassPourLayout.dropCenter) == .drop)
        #expect(model.hitTest(GlassPourLayout.restCenter(2)) == .row(2))
        #expect(model.hitTest(Vec2(2, 2)) == .outside)
        let choice = model.selectRow(3)
        #expect(choice == [.selected(3), .closing, .haptic])
        #expect(model.selectRow(1).isEmpty)
        _ = pump(&model, seconds: 1.6)
        #expect(model.phase == .closed)
        // A menu with no destructive row never wobbles.
        var plain = GlassPourModel(items: [
            GlassDropItem(title: "One", symbol: "1.circle", id: "1"),
            GlassDropItem(title: "Two", symbol: "2.circle", id: "2"),
        ])
        plain.activateDrop()
        var peak = 0.0
        for _ in 0..<100 {
            _ = plain.step(1.0 / 60)
            peak = max(peak, plain.rows.map { abs($0.wobble) }.max() ?? 0)
        }
        #expect(peak == 0 && plain.phase == .open)
    }

    @Test func voiceOverOpensWithoutTheHold() {
        var model = GlassPourModel()
        #expect(model.activateDrop() == [.opening])
        let moved = model.step(1.0 / 60)
        #expect(moved.isEmpty && model.rows[0].travel > 0 && model.rows[3].travel == 0)
        _ = pump(&model, seconds: 1.5)
        #expect(model.phase == .open)
        #expect(model.activateDrop() == [.closing])
        _ = pump(&model, seconds: 0.2)
        #expect(model.activateDrop() == [.opening] && model.phase == .opening)
    }

    @Test func closedMenuOnlyHitsTheDrop() {
        var model = GlassPourModel()
        #expect(model.hitTest(GlassPourLayout.dropCenter) == .drop)
        #expect(model.hitTest(GlassPourLayout.restCenter(0)) == .outside)
        #expect(model.step(0).isEmpty && model.step(-1).isEmpty && model.step(.nan).isEmpty)
        var jumped = GlassPourModel()
        #expect(jumped.step(1).isEmpty && near(jumped.time, GlassPourTuning.maxFrame))
    }

    @Test func reduceMotionCrossfadesInPlace() {
        var model = GlassPourModel(reduceMotion: true)
        model.pressDrop()
        _ = model.step(0.16)
        #expect(model.dropScale == 1)
        #expect(model.activateDrop() == [.opening])
        #expect(model.rows.map(\.center) == (0..<4).map { GlassPourLayout.restCenter($0) })
        #expect(model.necks.isEmpty && !model.usesGoo)
        #expect(model.rows.allSatisfy { $0.wobble == 0 && $0.scale == 1 && $0.opacity == 0 })
        _ = pump(&model, seconds: 0.12)
        #expect(model.phase == .opening && abs(model.fade - 0.5) < 1e-6 && abs(model.rows[3].opacity - model.fade) < 1e-12)
        #expect(model.rows[3].pinch == 1 && model.rows[3].center == GlassPourLayout.restCenter(3))
        let opened = pump(&model, seconds: 0.2)
        #expect(opened.contains(.opened) && opened.contains(.haptic) && model.phase == .open && model.fade == 1)
        #expect(model.rows.allSatisfy { abs($0.wobble) == 0 })
        #expect(model.hitTest(GlassPourLayout.restCenter(3)) == .row(3))
        #expect(model.selectRow(0).contains(.selected(0)))
        let closed = pump(&model, seconds: 0.3)
        #expect(closed.contains(.closed) && model.phase == .closed && model.fade == 0)
        #expect(model.rows.allSatisfy { !$0.isVisible && $0.wobble == 0 })
    }

    @Test func reduceMotionMidPourDropsTheWobble() {
        var model = GlassPourModel()
        model.activateDrop()
        _ = pump(&model, seconds: 0.7)
        #expect(model.phase == .opening && model.rows[3].wobble != 0 || model.rows[0].travel > 0.5)
        model.setReduceMotion(true)
        #expect(model.rows.allSatisfy { $0.wobble == 0 && $0.center.y == GlassPourLayout.restCenter($0.index).y })
        #expect(model.necks.isEmpty)
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
    }
}
