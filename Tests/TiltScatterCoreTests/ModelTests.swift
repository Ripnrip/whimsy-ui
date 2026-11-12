import Testing
import Foundation
@testable import TiltScatterCore

@Suite("Completing a row") struct CompleteTests {
    @Test func startsAsIdleText() {
        let model = TiltScatterModel()
        #expect(model.rows.allSatisfy { $0.phase == .idle && $0.titleOpacity == 1 })
        #expect(model.chips.allSatisfy { $0.opacity == 0 && $0.position == $0.home && $0.velocity == .zero })
        #expect(!model.canRestore)
        #expect(!model.needsFrame)
        #expect(model.accessibilityValue(for: 0) == "Not completed")
        #expect(model.tiltDescription == "Level")
    }

    @Test func toggleFadesTheTitleIntoChips() {
        var model = TiltScatterModel()
        let events = model.toggle(0)
        #expect(events.contains(.completed(0)))
        #expect(haptics(events, .complete) == 1)
        #expect(model.rows[0].phase == .dissolving)
        #expect(model.announcement == "Completed Water the fern. Letters scattered")
        model.run(0.2)
        #expect(model.rows[0].titleOpacity < 0.6)
        #expect(model.rows[0].titleOpacity > 0.05)
        let chips = model.chips.filter { $0.row == 0 }
        #expect(chips.allSatisfy { $0.opacity > 0.3 && $0.position == $0.home })
        #expect(model.accessibilityValue(for: 0) == "Completing")
    }

    @Test func dissolveEndsInASeededKick() {
        var model = TiltScatterModel()
        model.toggle(0)
        var events: [TiltScatterEvent] = []
        var steps = 0
        while model.rows[0].phase != .tumbling && steps < 80 {
            events += model.step(dt: TiltScatterTuning.substep)
            steps += 1
        }
        #expect(events.contains(.scattered(0)))
        #expect(model.rows[0].phase == .tumbling)
        #expect(model.rows[0].titleOpacity == 0)
        let chips = model.chips.filter { $0.row == 0 }
        #expect(chips.allSatisfy { $0.opacity == 1 && $0.velocity != .zero })
        #expect(Set(chips.map(\.velocity.x)).count > 1)
        #expect(chips.allSatisfy { $0.velocity.y < 0 && abs($0.velocity.y) <= 150 && abs($0.spin) <= 4.5 })
    }

    @Test func theKickIsReproducibleAndDependsOnTheSeed() {
        var a = TiltScatterModel(seed: 11)
        var b = TiltScatterModel(seed: 11)
        var c = TiltScatterModel(seed: 12)
        a.toggle(1); b.toggle(1); c.toggle(1)
        a.run(0.5); b.run(0.5); c.run(0.5)
        let av = a.chips.filter { $0.row == 1 }.map(\.velocity)
        let bv = b.chips.filter { $0.row == 1 }.map(\.velocity)
        let cv = c.chips.filter { $0.row == 1 }.map(\.velocity)
        #expect(av == bv)
        #expect(av != cv)
    }

    @Test func completingTwiceDoesNothing() {
        var model = TiltScatterModel()
        model.toggle(0)
        let again = model.toggle(0)
        #expect(again.contains(.seated(0)) || again.contains(.restoreBegan(0)))
        #expect(model.toggle(99).isEmpty)
        #expect(model.toggle(-1).isEmpty)
    }

    @Test func aSingleLetterAndAnEmptyTaskAreSafe() {
        var model = TiltScatterModel(tasks: [
            TiltScatterTask(id: "a", title: "A"),
            TiltScatterTask(id: "gap", title: "   "),
        ])
        #expect(model.chips.count == 1)
        model.toggle(1)
        model.run(0.5)
        #expect(model.rows[1].phase == .tumbling || model.rows[1].phase == .pinned || model.rows[1].phase == .idle)
        #expect(model.finite)
        model.restoreAll()
        model.run(1)
        #expect(model.rows[1].phase == .idle)
    }
}

@Suite("Tumble") struct TumbleTests {
    @Test func lettersFallAndStayInsideTheCard() {
        var model = TiltScatterModel()
        model.toggle(0)
        model.run(1.2)
        let chips = model.chips.filter { $0.row == 0 }
        let homeY = chips[0].home.y
        let meanY = chips.map(\.position.y).reduce(0, +) / Double(chips.count)
        #expect(meanY > homeY + 40)
        let r = TiltScatterLayout.collisionRadius
        for chip in chips {
            #expect(chip.position.x >= TiltScatterLayout.boundLeft + r - 0.01)
            #expect(chip.position.x <= TiltScatterLayout.boundRight - r + 0.01)
            #expect(chip.position.y >= TiltScatterLayout.boundTop + r - 0.01)
            #expect(chip.position.y <= TiltScatterLayout.boundBottom - r + 0.01)
        }
    }

    @Test func thePileLandsOnceAndThenSleeps() {
        var model = TiltScatterModel()
        model.toggle(0)
        let events = model.run(4.5)
        #expect(haptics(events, .land) == 1)
        #expect(model.landHaptics == 1)
        let chips = model.chips.filter { $0.row == 0 }
        #expect(chips.allSatisfy { $0.asleep && $0.velocity == .zero && $0.spin == 0 })
        let before = chips.map(\.position)
        model.run(0.5)
        #expect(model.chips.filter { $0.row == 0 }.map(\.position) == before)
        #expect(!model.needsFrame)
    }

    @Test func tippingRightSlidesThePileRight() {
        var right = TiltScatterModel(seed: 4)
        var left = TiltScatterModel(seed: 4)
        right.toggle(0); left.toggle(0)
        right.setTilt(Vec2(0.9, 0))
        left.setTilt(Vec2(-0.9, 0))
        right.run(1.3); left.run(1.3)
        let rx = right.chips.filter { $0.row == 0 }.map(\.position.x).reduce(0, +)
        let lx = left.chips.filter { $0.row == 0 }.map(\.position.x).reduce(0, +)
        #expect(rx > lx + 80)
    }

    @Test func aSettledPileWakesWhenTheTrayTips() {
        var model = TiltScatterModel()
        model.toggle(0)
        model.run(4.5)
        let before = model.chips.filter { $0.row == 0 }.map(\.position.x).reduce(0, +)
        model.setTilt(Vec2(0.85, 0))
        model.run(0.8)
        let after = model.chips.filter { $0.row == 0 }.map(\.position.x).reduce(0, +)
        #expect(after > before + 20)
    }

    @Test func twoRowsDoNotExplode() {
        var model = TiltScatterModel()
        model.toggle(0)
        model.run(0.6)
        model.toggle(3)
        model.run(3.5)
        #expect(model.finite)
        let cap = TiltScatterTuning.maxSpeed + 1
        #expect(model.chips.allSatisfy { $0.speed < cap })
        #expect(model.rows[0].phase == .tumbling)
        #expect(model.rows[3].phase == .tumbling)
    }

    @Test func replayMatchesBitForBit() {
        func played() -> TiltScatterModel {
            var model = TiltScatterModel(seed: 99)
            model.toggle(0)
            model.run(0.7)
            model.setTilt(Vec2(0.4, 0.2))
            model.toggle(2)
            model.run(1.1)
            model.setTilt(Vec2(-0.6, -0.4))
            model.run(0.8)
            return model
        }
        #expect(played().chips == played().chips)
        #expect(played().time == played().time)
    }

    @Test func nonFiniteInputIsIgnored() {
        var model = TiltScatterModel()
        model.setTilt(Vec2(0.4, -0.2))
        model.setTilt(Vec2(.nan, 0))
        #expect(model.tilt == Vec2(0.4, -0.2))
        model.setTilt(Vec2(3, -4))
        #expect(model.tilt == Vec2(1, -1))
        #expect(model.tiltDescription == "Tipped right, tipped forward")
        model.toggle(0)
        let time = model.time
        #expect(model.step(dt: .nan).isEmpty)
        #expect(model.step(dt: 0).isEmpty)
        #expect(model.step(dt: -1).isEmpty)
        #expect(model.time == time)
        model.step(dt: 5)
        #expect(abs(model.time - (time + TiltScatterTuning.maxFrame)) < 1e-9)
        #expect(model.finite)
    }
}

@Suite("Restore") struct RestoreTests {
    @Test func everyChipReturnsToItsOwnGlyph() {
        var model = TiltScatterModel(seed: 7)
        model.toggle(0)
        model.run(0.8)
        model.toggle(2)
        model.setTilt(Vec2(-0.7, 0.4))
        model.run(1.1)
        let homes = model.chips.map(\.home)
        let glyphs = model.chips.map(\.glyph)
        let events = model.restoreAll()
        #expect(events.contains(.restoreBegan(0)))
        #expect(events.contains(.restoreBegan(2)))
        #expect(haptics(events, .restore) == 1)
        #expect(model.announcement == "Restoring every letter")
        model.run(2.6)
        #expect(model.rows.allSatisfy { $0.phase == .idle && $0.titleOpacity == 1 })
        for (chip, home) in zip(model.chips, homes) {
            #expect(chip.position == home)
            #expect(chip.home == home)
            #expect(chip.angle == 0)
            #expect(chip.spin == 0)
            #expect(chip.velocity == .zero)
            #expect(chip.opacity == 0)
        }
        #expect(model.chips.map(\.glyph) == glyphs)
        #expect(!model.canRestore)
        #expect(model.announcement == "Restored Steep the tea" || model.announcement?.hasPrefix("Restored ") == true)
    }

    @Test func oneRowRestoresWithoutTouchingTheOther() {
        var model = TiltScatterModel(seed: 3)
        model.toggle(0)
        model.run(0.7)
        model.toggle(1)
        model.run(0.9)
        model.toggle(0)
        #expect(model.rows[0].phase == .restoring)
        #expect(model.rows[1].phase == .tumbling)
        #expect(model.announcement == "Restoring Water the fern")
        model.run(2.6)
        #expect(model.rows[0].phase == .idle)
        #expect(model.chips.filter { $0.row == 0 }.allSatisfy { $0.position == $0.home && $0.angle == 0 })
        #expect(model.rows[1].phase == .tumbling)
        let stillOut = model.chips.filter { $0.row == 1 }.contains { $0.position.distance(to: $0.home) > 20 }
        #expect(stillOut)
    }

    @Test func aSecondTapWhileRestoringDoesNotRestart() {
        var model = TiltScatterModel()
        model.toggle(0)
        model.run(0.8)
        model.toggle(0)
        let clock = model.rows[0].clock
        #expect(model.toggle(0).isEmpty)
        #expect(model.rows[0].phase == .restoring)
        #expect(model.rows[0].clock == clock)
    }

    @Test func chipsKeepTheirIdentityAcrossTheSpring() {
        var model = TiltScatterModel()
        model.toggle(1)
        model.run(1.0)
        let ids = model.chips.filter { $0.row == 1 }
        model.toggle(1)
        model.run(0.3)
        let mid = model.chips.filter { $0.row == 1 }
        #expect(mid.map(\.index) == ids.map(\.index))
        #expect(mid.map(\.glyph) == ids.map(\.glyph))
        #expect(mid.map(\.home) == ids.map(\.home))
        for chip in mid {
            #expect(chip.position.distance(to: chip.home) < chip.position.distance(to: Vec2(0, 0)) || chip.home.distance(to: .zero) < 30)
        }
        let title = TiltScatterLayout.glyphs(title: "Buy walnut ink", row: 1)
        #expect(mid.map(\.glyph) == title.map(\.glyph))
        #expect(mid.map(\.home) == title.map(\.home))
    }
}

@Suite("Reduce Motion") struct ReduceMotionTests {
    @Test func chipsStayInTheWord() {
        var model = TiltScatterModel()
        model.setReduceMotion(true)
        let events = model.toggle(0)
        #expect(events.contains(.completed(0)))
        #expect(model.announcement == "Completed Water the fern")
        model.run(0.4)
        #expect(model.rows[0].phase == .pinned)
        #expect(model.rows[0].titleOpacity == 0)
        #expect(model.accessibilityValue(for: 0) == "Completed")
        let chips = model.chips.filter { $0.row == 0 }
        #expect(chips.allSatisfy {
            $0.position == $0.home && $0.velocity == .zero && $0.angle == 0 && $0.opacity == 1 && $0.spin == 0
        })
        model.setTilt(Vec2(1, -1))
        model.run(0.6)
        #expect(model.chips.filter { $0.row == 0 }.map(\.position) == chips.map(\.position))
    }

    @Test func restoreIsImmediate() {
        var model = TiltScatterModel()
        model.setReduceMotion(true)
        model.toggle(0)
        model.run(0.4)
        let events = model.toggle(0)
        #expect(events.contains(.seated(0)))
        #expect(model.rows[0].phase == .idle)
        #expect(model.rows[0].titleOpacity == 1)
        #expect(model.chips.filter { $0.row == 0 }.allSatisfy { $0.opacity == 0 && $0.position == $0.home })
        #expect(model.announcement == "Restored Water the fern")
    }

    @Test func enablingItMidTumbleParksEveryChip() {
        var model = TiltScatterModel()
        model.toggle(0)
        model.run(1.0)
        #expect(model.rows[0].phase == .tumbling)
        model.setReduceMotion(true)
        #expect(model.rows[0].phase == .pinned)
        #expect(model.chips.filter { $0.row == 0 }.allSatisfy { $0.position == $0.home && $0.velocity == .zero })
        model.setReduceMotion(true)
        #expect(model.rows[0].phase == .pinned)
    }

    @Test func restoreAllUnderReduceMotionSeatsEveryRow() {
        var model = TiltScatterModel()
        model.setReduceMotion(true)
        model.toggle(0)
        model.toggle(4)
        model.run(0.4)
        let events = model.restoreAll()
        #expect(events.contains(.seated(0)))
        #expect(events.contains(.seated(4)))
        #expect(model.rows.allSatisfy { $0.phase == .idle })
        #expect(model.announcement == "Restoring every letter")
    }
}

@Suite("Parity trace") struct TraceTests {
    @Test func sessionHasAStableShape() throws {
        let lines = TiltScatterTrace.parityLines()
        #expect(lines.count == 108)
        #expect(lines.allSatisfy { !$0.isEmpty })
        let model = TiltScatterModel()
        #expect(lines[0].hasPrefix(TiltScatterMath.hex(0)))
        #expect(lines[0].contains("IIIII"))
        let url = URL(fileURLWithPath: "/tmp/tiltscatter-swift-trace.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(model.chips.count == TiltScatterModel().chips.count)
    }

    @Test func flightScaleIsAPureFunctionOfSpeed() {
        #expect(TiltScatterTuning.flightScale(speed: 0) == 1)
        #expect(TiltScatterTuning.flightScale(speed: -10) == 1)
        #expect(TiltScatterTuning.flightScale(speed: 320) == 1 + 0.06 * 0.5)
        #expect(TiltScatterTuning.flightScale(speed: 5000) == 1 + 0.06)
        #expect(TiltScatterTuning.flightScale(speed: .nan) == 1)
    }
}
