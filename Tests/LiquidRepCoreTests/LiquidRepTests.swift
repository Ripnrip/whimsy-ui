import Foundation
import Testing
@testable import LiquidRepDialCore

@Suite("Fill") struct LiquidRepFillTests {
    @Test func anEmptyDialSitsAtZero() {
        let model = LiquidRepModel()
        #expect(model.reps == 0)
        #expect(model.goal == 20)
        #expect(model.targetFill == 0)
        #expect(model.displayedFill == 0)
        #expect(model.fillVelocity == 0)
        #expect(model.sloshAngle == 0)
        #expect(model.meniscus == 0)
        #expect(model.rim.trim == 0)
        #expect(!model.atGoal)
        #expect(!model.needsClock)
        #expect(model.readout == "0")
    }

    @Test func oneRepKicksPastTheMarkAndSettles() {
        var model = LiquidRepModel(goal: 20)
        let events = model.addRep()
        #expect(events == [.tick])
        #expect(model.reps == 1)
        #expect(abs(model.targetFill - 0.05) < 1e-12)
        #expect(model.displayedFill == 0)
        #expect(abs(model.fillVelocity - LiquidRepTuning.impulse) < 1e-12)
        #expect(model.needsClock)
        var peak = 0.0
        var sawWobble = false
        for _ in 0..<90 {
            model.step(LiquidRepReel.dt)
            peak = max(peak, model.displayedFill)
            if abs(model.meniscus) > 0.02 { sawWobble = true }
        }
        #expect(peak > model.targetFill + 0.05)
        #expect(peak < 0.25)
        #expect(abs(model.displayedFill - model.targetFill) < 0.01)
        #expect(abs(model.fillVelocity) < 0.05)
        #expect(sawWobble)
        #expect(model.meniscusEnvelope < 0.05)
        #expect(model.addRep() == [.tick])
        #expect(model.reps == 2)
    }

    @Test func theSameInputsStayOnTheSamePath() {
        var left = LiquidRepModel(reps: 4, goal: 20)
        var right = LiquidRepModel(reps: 4, goal: 20)
        #expect(left.setReps(7) == right.setReps(7))
        left.setTilt(LiquidTilt(roll: 0.2, pitch: -0.1))
        right.setTilt(LiquidTilt(roll: 0.2, pitch: -0.1))
        for _ in 0..<36 {
            left.step(LiquidRepReel.dt)
            right.step(LiquidRepReel.dt)
            #expect(left.displayedFill == right.displayedFill)
            #expect(left.sloshAngle == right.sloshAngle)
            #expect(left.meniscus == right.meniscus)
            #expect(left.glow == right.glow)
            #expect(left.rim.leading == right.rim.leading)
        }
        #expect(left == right)
        #expect(LiquidRepReel.model(atFrame: 40) == LiquidRepReel.model(atFrame: 40))
    }

    @Test func aLongFrameOnlyAdvancesByTheCap() {
        var model = LiquidRepModel(goal: 20)
        model.step(.nan)
        model.step(0)
        model.step(-0.2)
        #expect(model.displayedFill == 0)
        #expect(model.elapsed == 0)
        #expect(model.addRep() == [.tick])
        let kicked = model
        model.step(.nan)
        model.step(0)
        #expect(model == kicked)
        model.step(1)
        #expect(abs(model.elapsed - WhimsySpring.maxFrame) < 1e-12)
        #expect(model.displayedFill > 0)
        #expect(model.displayedFill < model.targetFill + 0.2)
        #expect(model.reps == 1)
    }

    @Test func crossingTheGoalTicksOnceAndAJumpCountsEveryRep() {
        var model = LiquidRepModel(reps: 19, goal: 20)
        #expect(model.addRep() == [.tick, .goalReached])
        #expect(model.atGoal)
        #expect(model.addRep() == [.tick])
        #expect(model.reps == 21)
        #expect(model.targetFill == 1)
        var fresh = LiquidRepModel(goal: 20)
        let jumped = fresh.setReps(20)
        #expect(jumped.filter { $0 == .tick }.count == 20)
        #expect(jumped.contains(.goalReached))
        #expect(fresh.setReps(20).isEmpty)
        #expect(fresh.setReps(18).isEmpty)
        #expect(fresh.reps == 18)
        #expect(!fresh.atGoal)
    }

    @Test func countsAndGoalsClamp() {
        let low = LiquidRepModel(reps: -3, goal: 0)
        #expect(low.reps == 0)
        #expect(low.goal == 1)
        #expect(low.targetFill == 0)
        var high = LiquidRepModel(reps: 5_000, goal: 20)
        #expect(high.reps == LiquidRepTuning.maxReps)
        #expect(high.targetFill == 1)
        #expect(high.canAddRep == false)
        #expect(high.addRep().isEmpty)
        var model = LiquidRepModel(reps: 10, goal: 20)
        model.setGoal(0)
        #expect(model.goal == 1)
        #expect(model.targetFill == 1)
        #expect(model.atGoal)
        model.setGoal(1)
        #expect(model.goal == 1)
        model.setTilt(LiquidTilt(roll: .nan, pitch: .infinity))
        #expect(model.tilt == .zero)
    }
}

@Suite("Slosh and meniscus") struct LiquidRepSloshTests {
    @Test func thePoolSlidesTowardTheLowSide() {
        var down = LiquidRepModel(reps: 10, goal: 20)
        down.setTilt(LiquidTilt(roll: 0.15, pitch: 0.55))
        for _ in 0..<40 { down.step(LiquidRepReel.dt) }
        #expect(down.sloshAngle > 0.25)
        #expect(down.sloshAngle <= LiquidRepTuning.maxSlosh + 0.08)

        var left = LiquidRepModel(reps: 10, goal: 20)
        left.setTilt(LiquidTilt(roll: -0.55, pitch: -0.2))
        for _ in 0..<40 { left.step(LiquidRepReel.dt) }
        #expect(left.sloshAngle < -0.2)

        let aimed = LiquidRepMath.sloshTarget(fill: 0.5, tilt: LiquidTilt(roll: 0.15, pitch: 0.55))
        #expect(aimed > 0.3)
        #expect(aimed <= LiquidRepTuning.maxSlosh + 1e-12)
    }

    @Test func anEmptyOrFullRingDoesNotSlosh() {
        var empty = LiquidRepModel(reps: 0, goal: 20)
        empty.setTilt(LiquidTilt(roll: 0.4, pitch: 0.4))
        for _ in 0..<30 { empty.step(LiquidRepReel.dt) }
        #expect(empty.sloshAngle == 0)
        #expect(LiquidRepMath.pool(0) == 0)
        #expect(LiquidRepMath.pool(1) == 0)
        #expect(abs(LiquidRepMath.pool(0.5) - 1) < 1e-6)

        var full = LiquidRepModel(reps: 20, goal: 20)
        full.setTilt(LiquidTilt(roll: -0.5, pitch: 0.4))
        for _ in 0..<30 { full.step(LiquidRepReel.dt) }
        #expect(abs(full.sloshAngle) < 1e-6)
        #expect(LiquidRepMath.sloshTarget(fill: 1, tilt: LiquidTilt(roll: 0.4, pitch: 0.4)) == 0)
        #expect(LiquidRepMath.sloshTarget(fill: 0.5, tilt: .zero) == 0)
    }

    @Test func theLeadingEdgeSitsOnTheRim() {
        let top = LiquidRepMath.point(angle: 0, radius: LiquidRepTuning.ringRadius)
        #expect(abs(top.x - LiquidRepTuning.dialCenter.x) < 1e-9)
        #expect(abs(top.y - (LiquidRepTuning.dialCenter.y - LiquidRepTuning.ringRadius)) < 1e-9)
        let right = LiquidRepMath.point(angle: LiquidRepMath.halfPi, radius: LiquidRepTuning.ringRadius)
        #expect(right.x > LiquidRepTuning.dialCenter.x + 100)
        #expect(abs(right.y - LiquidRepTuning.dialCenter.y) < 1e-6)

        var model = LiquidRepModel(reps: 10, goal: 20)
        for _ in 0..<12 { model.step(LiquidRepReel.dt) }
        let rim = model.rim
        let dx = rim.leading.x - rim.center.x
        let dy = rim.leading.y - rim.center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        #expect(abs(distance - (rim.radius + rim.bulge)) < 1e-9)
        #expect(rim.trim > 0.4)
        #expect(rim.trim < 0.7)
        #expect(abs(LiquidRepTuning.dialDiameter - 220) < 1e-9)
        #expect(abs(LiquidRepTuning.ringRadius - 102) < 1e-9)
    }

    @Test func theGoalGlowBreathesAndAPartialFillDoesNot() {
        let partial = LiquidRepMath.glow(fill: 0.4, atGoal: false, elapsed: 0.4, reduceMotion: false)
        #expect(abs(partial - (LiquidRepTuning.glowFloor + LiquidRepTuning.glowSpan * 0.4)) < 1e-12)
        let early = LiquidRepMath.glow(fill: 1, atGoal: true, elapsed: 0.1, reduceMotion: false)
        let later = LiquidRepMath.glow(fill: 1, atGoal: true, elapsed: 0.7, reduceMotion: false)
        let held = LiquidRepMath.glow(fill: 1, atGoal: true, elapsed: 0.7, reduceMotion: true)
        #expect(early != later)
        #expect(abs(early - later) > 0.02)
        #expect(held == LiquidRepTuning.goalGlowSteady)
        #expect(held > partial)
    }
}

@Suite("Reduce Motion") struct LiquidRepReduceTests {
    @Test func theFillCrossfadesWithoutOvershoot() {
        var model = LiquidRepModel(goal: 20, reduceMotion: true)
        let events = model.setReps(12)
        #expect(events.filter { $0 == .tick }.count == 12)
        #expect(!events.contains(.goalReached))
        #expect(model.displayedFill == 0)
        #expect(model.sloshAngle == 0)
        #expect(model.meniscus == 0)
        #expect(model.fillVelocity == 0)
        #expect(model.needsClock)
        let target = model.targetFill
        var last = model.displayedFill
        for _ in 0..<30 {
            model.step(LiquidRepReel.dt)
            #expect(model.displayedFill + 1e-12 >= last)
            #expect(model.displayedFill <= target + 1e-12)
            #expect(model.sloshAngle == 0)
            #expect(model.meniscus == 0)
            #expect(model.meniscusEnvelope == 0)
            last = model.displayedFill
        }
        #expect(abs(model.displayedFill - target) < 1e-12)
        #expect(abs(target - 0.6) < 1e-12)
        #expect(!model.needsClock)
        let glow = model.glow
        model.step(0.4)
        #expect(model.displayedFill == target)
        #expect(model.glow == glow)
    }

    @Test func turningItOnDropsTheOvershootTheSloshAndTheWobble() {
        var model = LiquidRepModel(reps: 8, goal: 20)
        #expect(model.addRep().count == 1)
        model.setTilt(LiquidTilt(roll: 0.3, pitch: 0.45))
        for _ in 0..<10 { model.step(LiquidRepReel.dt) }
        #expect(model.displayedFill > model.targetFill)
        #expect(model.sloshAngle != 0)
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        #expect(model.sloshAngle == 0)
        #expect(model.meniscus == 0)
        #expect(model.fillVelocity == 0)
        let shown = model.displayedFill
        #expect(shown > model.targetFill)
        model.step(LiquidRepReel.dt)
        #expect(model.displayedFill < shown)
        #expect(model.displayedFill > model.targetFill)
        model.setReduceMotion(true)
        #expect(model.displayedFill < shown)
    }

    @Test func aTiltStoredUnderReduceMotionWaits() {
        var model = LiquidRepModel(reps: 10, goal: 20, reduceMotion: true)
        model.setTilt(LiquidTilt(roll: 0.2, pitch: 0.5))
        for _ in 0..<20 { model.step(LiquidRepReel.dt) }
        #expect(model.sloshAngle == 0)
        #expect(model.tilt.pitch == 0.5)
        model.setReduceMotion(false)
        #expect(model.sloshAngle == 0)
        model.step(LiquidRepReel.dt)
        #expect(model.sloshAngle > 0)
    }
}

@Suite("Voice and the reel") struct LiquidRepVoiceTests {
    @Test func voiceOverReadsTheCountAndTheGoal() {
        let model = LiquidRepModel(reps: 12, goal: 20)
        #expect(model.accessibilityLabel == "Liquid rep dial")
        #expect(model.accessibilityValue == "12 of 20 reps")
        #expect(model.canAddRep)
        let empty = LiquidRepModel()
        #expect(empty.accessibilityValue == "0 of 20 reps")
        let done = LiquidRepModel(reps: 20, goal: 20)
        #expect(done.accessibilityValue == "20 of 20 reps")
        #expect(done.atGoal)
        #expect(LiquidRepTuning.addRepAction == "Add rep")
        #expect(abs(LiquidRepTuning.bounce - 0.4) < 1e-12)
        #expect(abs(LiquidRepTuning.dampingRatio - 0.6) < 1e-12)
    }

    @Test func theReelHitsEveryStill() {
        let idle = LiquidRepReel.model(atFrame: 12)
        #expect(idle.reps == 0)
        #expect(idle.displayedFill == 0)
        #expect(!idle.reduceMotion)
        #expect(idle.rim.trim == 0)

        let over = LiquidRepReel.model(atFrame: 38)
        #expect(over.reps == 1)
        #expect(over.displayedFill > over.targetFill + 0.05)
        #expect(abs(over.meniscus) > 0.01 || over.meniscusEnvelope > 0.2)

        let mid = LiquidRepReel.model(atFrame: 190)
        #expect(mid.reps == 10)
        #expect(abs(mid.displayedFill - 0.5) < 0.04)
        #expect(abs(mid.sloshAngle) < 0.05)

        let slosh = LiquidRepReel.model(atFrame: 226)
        #expect(slosh.reps == 10)
        #expect(slosh.sloshAngle > 0.3)
        #expect(abs(slosh.displayedFill - 0.5) < 0.05)

        let near = LiquidRepReel.model(atFrame: 306)
        #expect(near.reps == 17)
        #expect(near.displayedFill > 0.75)
        #expect(near.displayedFill < 0.95)
        #expect(!near.atGoal)

        let goal = LiquidRepReel.model(atFrame: 366)
        #expect(goal.reps == 20)
        #expect(goal.atGoal)
        #expect(goal.displayedFill > 0.9)
        #expect(goal.glow > 0.75)
        #expect(abs(goal.sloshAngle) < 0.08)

        let reduced = LiquidRepReel.model(atFrame: 448)
        #expect(reduced.reduceMotion)
        #expect(reduced.reps == 12)
        #expect(reduced.sloshAngle == 0)
        #expect(reduced.meniscus == 0)
        #expect(reduced.displayedFill > 0.15)
        #expect(reduced.displayedFill < reduced.targetFill)
        var still = reduced
        still.step(0.05)
        #expect(still.meniscus == 0)
        #expect(still.sloshAngle == 0)
        #expect(still.displayedFill >= reduced.displayedFill)
        #expect(still.displayedFill <= still.targetFill + 1e-12)

        #expect(LiquidRepReel.stills.count == 7)
        #expect(LiquidRepReel.stills.map(\.name) == [
            "Idle empty",
            "First tap overshoot",
            "Mid fill",
            "Near goal",
            "Goal reached glow",
            "Tilt slosh",
            "Reduce Motion",
        ])
        #expect(LiquidRepReel.duration > 7)
        #expect(LiquidRepReel.duration < 9)
        #expect(LiquidRepReel.model(at: 38.0 / 60.0) == over)
        #expect(LiquidRepReel.model(at: 0) == LiquidRepReel.model(atFrame: 0))
    }
}
