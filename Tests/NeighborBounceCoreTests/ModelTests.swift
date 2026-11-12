import Foundation
import Testing
@testable import NeighborBounceCore

@Suite("Selection") struct SelectionTests {
    @Test func startsSeatedOnTheSelection() {
        let model = NeighborBounceModel(count: 6, selection: 2)
        #expect(model.selection == 2)
        #expect(model.time == 0)
        #expect(model.pendingCount == 0)
        #expect(model.indicatorX == NeighborBounceLayout.restCenter(index: 2, count: 6).x)
        #expect(model.indicatorVelocity == 0)
        #expect(model.scale(2) == NeighborBounceTuning.selectedScale)
        #expect(model.scale(0) == 1)
        for i in 0..<6 {
            #expect(model.offset(i) == .zero)
            #expect(model.velocity(i) == .zero)
            #expect(model.pose(i).lift == 0)
        }
    }

    @Test func selectSchedulesEveryNeighbourAndDoesNotMoveAnything() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        let before = (0..<6).map { (model.offset($0), model.velocity($0), model.indicatorX) }
        let events = model.select(3)
        #expect(events == [.selected(3)])
        #expect(model.selection == 3)
        #expect(model.pendingCount == 5)
        #expect(model.launches == 0)
        for i in 0..<6 {
            #expect(model.offset(i) == before[i].0)
            #expect(model.velocity(i) == before[i].1)
        }
        #expect(model.indicatorX == before[0].2)
        let fires = model.pending.map(\.fireAt)
        #expect(fires == fires.sorted())
    }

    @Test func staggerMatchesDistanceAndTheSelectedTickIsNotKicked() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(2)
        #expect(model.pending.allSatisfy { $0.index != 2 })
        for kick in model.pending {
            let distance = abs(kick.index - 2)
            #expect(kick.fireAt == NeighborBounceTuning.stagger * Double(distance))
            let sign = kick.index > 2 ? 1.0 : -1.0
            #expect(kick.velocity == NeighborBounceWave.impulse(distance: distance, sign: sign))
        }
        let sameDistance = model.pending.filter { abs($0.index - 2) == 1 }
        #expect(sameDistance.map(\.index) == [1, 3])
        #expect(sameDistance[0].fireAt == sameDistance[1].fireAt)
        #expect(sameDistance[0].velocity.x == -sameDistance[1].velocity.x)
    }

    @Test func choosingTheSameTickNudgesInsteadOfChangingSelection() {
        var model = NeighborBounceModel(count: 6, selection: 2)
        #expect(model.select(2) == [.nudged(2)])
        #expect(model.selection == 2)
        #expect(model.pendingCount == 5)
    }

    @Test func outOfRangeSelectClamps() {
        var model = NeighborBounceModel(count: 5, selection: 1)
        #expect(model.select(-8) == [.selected(0)])
        #expect(model.selection == 0)
        #expect(model.select(40) == [.selected(4)])
        #expect(model.selection == 4)
        #expect(model.select(4) == [.nudged(4)])
    }

    @Test func aNewSelectionDropsKicksThatHaveNotFired() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(0)
        for _ in 0..<NeighborBounceTuning.staggerSteps {
            _ = model.step(NeighborBounceTuning.substep)
        }
        #expect(model.launches == 1)
        #expect(model.pending.contains { $0.index == 2 })
        #expect(model.velocity(2) == .zero)
        _ = model.select(5)
        #expect(model.velocity(2) == .zero)
        #expect(!model.pending.contains { $0.index == 2 && $0.fireAt <= model.time + NeighborBounceTuning.stagger })
        for _ in 0..<NeighborBounceTuning.staggerSteps {
            _ = model.step(NeighborBounceTuning.substep)
        }
        // Distance from 5 to 2 is 3, so the replacement kick is still waiting.
        #expect(abs(model.velocity(2).x) < 1e-8)
        #expect(abs(model.velocity(2).y) < 1e-8)
    }
}

@Suite("Motion") struct MotionTests {
    @Test func theFirstKickLeavesNeighboursGoingUpAndOut() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(2)
        var launched: [NeighborBounceEvent] = []
        for _ in 0..<NeighborBounceTuning.staggerSteps {
            launched += model.step(NeighborBounceTuning.substep).filter(isLaunched)
        }
        #expect(launched == [.launched(1), .launched(3)])
        #expect(model.velocity(1).x < 0)
        #expect(model.velocity(3).x > 0)
        #expect(model.velocity(1).y < 0)
        #expect(model.velocity(3).y < 0)
        #expect(model.velocity(2) == .zero)
        // One substep of integration cannot undo the kick's direction.
        #expect(model.offset(1).y < 0)
        #expect(model.offset(3).y < 0)
    }

    @Test func peaksDecayWithDistanceAndTheSelectionStaysDown() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(2)
        var peakY = [Double](repeating: 0, count: 6)
        var minX = [Double](repeating: 0, count: 6)
        var maxX = [Double](repeating: 0, count: 6)
        for _ in 0..<360 {
            _ = model.step(NeighborBounceTuning.substep)
            for i in 0..<6 {
                peakY[i] = max(peakY[i], -model.offset(i).y)
                minX[i] = min(minX[i], model.offset(i).x)
                maxX[i] = max(maxX[i], model.offset(i).x)
            }
        }
        #expect(peakY[2] < 1)
        #expect(peakY[1] > 30)
        #expect(peakY[3] > 30)
        #expect(peakY[1] > peakY[0])
        #expect(peakY[3] > peakY[4])
        #expect(peakY[4] > peakY[5])
        #expect(minX[0] < -1)
        #expect(minX[1] < minX[0])
        #expect(maxX[3] > 1)
        #expect(maxX[4] > 1)
        #expect(maxX[3] > maxX[4])
    }

    @Test func landingsAreRateLimitedAndTheRowEventuallySits() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(2)
        var times: [Double] = []
        var sawSettled = false
        for _ in 0..<800 {
            let events = model.step(NeighborBounceTuning.substep)
            if events.contains(where: isLanded) { times.append(model.time) }
            if events.contains(.settled) { sawSettled = true }
        }
        #expect(times.count >= 1)
        #expect(times.count == model.landings)
        #expect(model.suppressedLandings > 0)
        for i in 1..<times.count {
            #expect(times[i] - times[i - 1] >= NeighborBounceTuning.hapticGap - 1e-9)
        }
        #expect(sawSettled)
        #expect(model.pendingCount == 0)
        for i in 0..<6 {
            #expect(abs(model.offset(i).x) < 0.05)
            #expect(abs(model.offset(i).y) < 0.05)
            #expect(abs(model.velocity(i).x) < 0.5)
        }
        #expect(abs(model.scale(2) - NeighborBounceTuning.selectedScale) < 1e-3)
        #expect(abs(model.scale(0) - 1) < 1e-3)
        let target = NeighborBounceLayout.restCenter(index: 2, count: 6).x
        #expect(abs(model.indicatorX - target) < 0.05)
    }

    @Test func anEndSelectionOnlyLaunchesOneSide() {
        var model = NeighborBounceModel(count: 7, selection: 3)
        _ = model.select(0)
        #expect(model.pending.allSatisfy { $0.index > 0 })
        #expect(model.pending.count == 6)
        _ = model.run(0.5)
        #expect(model.offset(0).x <= 0.5)
    }

    @Test func poseLiftAndSquashFollowTheOffset() {
        var model = NeighborBounceModel(count: 6, selection: 1)
        _ = model.select(1)
        var sawStretch = false
        for _ in 0..<40 {
            _ = model.step(NeighborBounceTuning.substep)
            let pose = model.pose(2)
            #expect(abs(pose.lift - max(0, -model.offset(2).y)) < 1e-12)
            #expect(abs(pose.center.x - (NeighborBounceLayout.restCenter(index: 2, count: 6).x + model.offset(2).x)) < 1e-9)
            if model.velocity(2).y < -100 {
                #expect(pose.scaleY > pose.scaleX)
                sawStretch = true
            }
        }
        #expect(sawStretch)
    }

    @Test func theIndicatorTravelsTowardTheNewTickWithoutAJump() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        let start = model.indicatorX
        _ = model.select(5)
        #expect(model.indicatorX == start)
        var previous = model.indicatorX
        var maxJump = 0.0
        for _ in 0..<500 {
            _ = model.step(NeighborBounceTuning.substep)
            maxJump = max(maxJump, abs(model.indicatorX - previous))
            previous = model.indicatorX
        }
        #expect(maxJump < 8)
        let target = NeighborBounceLayout.restCenter(index: 5, count: 6).x
        #expect(abs(model.indicatorX - target) < 0.05)
        #expect(model.indicatorX > start + 40)
    }

    @Test func ignoredStepsLeaveTheTraceAlone() {
        var model = NeighborBounceModel()
        _ = model.select(1)
        let line = model.traceLine()
        #expect(model.step(.nan).isEmpty)
        #expect(model.step(.infinity).isEmpty)
        #expect(model.step(-0.2).isEmpty)
        #expect(model.step(0).isEmpty)
        #expect(model.traceLine() == line)
        #expect(model.time == 0)
    }

    @Test func aLongFrameMatchesTwentyFourSubsteps() {
        var whole = NeighborBounceModel(count: 6, selection: 0)
        var parts = NeighborBounceModel(count: 6, selection: 0)
        _ = whole.select(4)
        _ = parts.select(4)
        _ = whole.step(10)
        for _ in 0..<24 { _ = parts.step(NeighborBounceTuning.substep) }
        #expect(whole.traceLine() == parts.traceLine())
        #expect(whole.time == parts.time)
        // 24 additions of 1/240 land one ulp under the multiplied maxFrame. Same steps, same trace.
        #expect(abs(whole.time - NeighborBounceTuning.maxFrame) < 1e-9)
    }
}

@Suite("Rapid selections") struct ContinuityTests {
    @Test func selectingMidFlightDoesNotMoveTheCurrentSample() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(1)
        for _ in 0..<20 { _ = model.step(NeighborBounceTuning.substep) }
        let offsets = (0..<6).map { model.offset($0) }
        let velocities = (0..<6).map { model.velocity($0) }
        let scales = (0..<6).map { model.scale($0) }
        let indicator = model.indicatorX
        let indicatorV = model.indicatorVelocity
        _ = model.select(4)
        #expect((0..<6).map { model.offset($0) } == offsets)
        #expect((0..<6).map { model.velocity($0) } == velocities)
        #expect((0..<6).map { model.scale($0) } == scales)
        #expect(model.indicatorX == indicator)
        #expect(model.indicatorVelocity == indicatorV)
        #expect(model.selection == 4)
    }

    @Test func burstOfSelectionsStaysFiniteAndComesToRest() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        for index in [0, 5, 1, 4, 2, 3, 0, 5, 2] {
            _ = model.select(index)
            for _ in 0..<5 { _ = model.step(NeighborBounceTuning.substep) }
            for i in 0..<6 {
                #expect(model.offset(i).x.isFinite && model.offset(i).y.isFinite)
                #expect(model.velocity(i).x.isFinite && model.velocity(i).y.isFinite)
                #expect(model.pose(i).scaleX.isFinite && model.pose(i).scaleY.isFinite)
            }
            #expect(model.indicatorX.isFinite)
        }
        #expect(model.selection == 2)
        _ = model.run(3)
        #expect(model.isResting)
        #expect(model.settles >= 1)
        for i in 0..<6 {
            #expect(abs(model.offset(i).y) < 0.05)
        }
    }

    @Test func twoRunsWithTheSameInputsMatch() {
        func script() -> [String] {
            var model = NeighborBounceModel(count: 7, selection: 1)
            var lines = [model.traceLine()]
            for index in [0, 6, 3, 3, 1] {
                _ = model.select(index)
                lines.append(model.traceLine())
                for _ in 0..<18 {
                    _ = model.step(NeighborBounceTuning.substep)
                    lines.append(model.traceLine())
                }
            }
            return lines
        }
        #expect(script() == script())
    }
}

@Suite("Reduce Motion") struct ReduceMotionTests {
    @Test func selectionSnapsAndNothingLaunches() {
        var model = NeighborBounceModel(count: 6, selection: 1, reduceMotion: true)
        let events = model.select(4)
        #expect(events == [.selected(4)])
        #expect(model.pendingCount == 0)
        #expect(model.indicatorX == NeighborBounceLayout.restCenter(index: 4, count: 6).x)
        #expect(model.indicatorVelocity == 0)
        #expect(model.scale(4) == NeighborBounceTuning.selectedScale)
        #expect(model.scale(1) == 1)
        for i in 0..<6 {
            #expect(model.offset(i) == .zero)
            #expect(model.velocity(i) == .zero)
        }
        let later = model.run(0.8)
        #expect(!later.contains(where: isLanded))
        #expect(!later.contains(where: isLaunched))
        #expect(model.landings == 0 && model.launches == 0)
        #expect(model.spokenSelection(titles: NeighborTick.demo.map(\.title)) == "Plum, selected")
    }

    @Test func enablingItMidWaveSeatsEveryTick() {
        var model = NeighborBounceModel(count: 6, selection: 0)
        _ = model.select(3)
        _ = model.run(0.12)
        #expect(model.offset(2).y < -1 || model.offset(4).y < -1)
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        #expect(model.pendingCount == 0)
        #expect(model.indicatorX == NeighborBounceLayout.restCenter(index: 3, count: 6).x)
        for i in 0..<6 {
            #expect(model.offset(i) == .zero)
            #expect(model.velocity(i) == .zero)
        }
        let events = model.step(NeighborBounceTuning.substep)
        #expect(events == [.settled])
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        #expect(model.step(NeighborBounceTuning.substep).isEmpty)
    }

    @Test func turningItOffDoesNotInventAWave() {
        var model = NeighborBounceModel(count: 6, selection: 2, reduceMotion: true)
        model.setReduceMotion(false)
        #expect(!model.reduceMotion)
        #expect(model.pendingCount == 0)
        #expect(model.offset(0) == .zero)
        let line = model.traceLine()
        _ = model.step(NeighborBounceTuning.substep)
        // A seated row stays seated. Time moves, so the trace changes, but nothing launches.
        #expect(model.launches == 0)
        #expect(model.offset(1) == .zero)
        #expect(model.traceLine() != line)
    }
}

@Suite("Parity trace") struct TraceTests {
    @Test func sessionHasAStableShape() throws {
        let lines = NeighborBounceTrace.parityLines()
        #expect(lines.count == 18 + 6 + 1 + 147)
        #expect(lines.allSatisfy { !$0.isEmpty })
        #expect(lines[0].hasPrefix("L 5 0 "))
        #expect(lines[18].hasPrefix("K 1 "))
        #expect(lines[24] == "F 6 ink,sage,clay,gold,plum,tide")
        let url = URL(fileURLWithPath: "/tmp/neighborbounce-swift-trace.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func hexFoldsNegativeZero() {
        #expect(NeighborBounceMath.hex(0) == NeighborBounceMath.hex(-0.0))
        #expect(NeighborBounceMath.hex(0).count == 16)
        #expect(NeighborBounceMath.hex(1) == "3ff0000000000000")
        #expect(NeighborBounceMath.hex(-960) == NeighborBounceMath.hex(-960.0))
    }
}
