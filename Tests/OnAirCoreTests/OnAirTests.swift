import Foundation
import Testing
@testable import OnAirCore

extension OnAirModel {
    @discardableResult
    mutating func run(_ seconds: Double, fps: Double = 60) -> [OnAirEvent] {
        var out: [OnAirEvent] = []
        let n = Int((seconds * fps).rounded())
        for _ in 0..<n { out += step(1 / fps) }
        return out
    }
}

private func haptics(_ events: [OnAirEvent]) -> Int {
    events.reduce(0) { partial, event in
        if case .haptic = event { return partial + 1 }
        return partial
    }
}

private func committed(_ events: [OnAirEvent]) -> [Bool] {
    events.compactMap { event in
        if case .committed(let on) = event { return on }
        return nil
    }
}

private var pillMidY: Double { OnAirTuning.pillY + OnAirTuning.pillHeight / 2 }

@Suite("Clock") struct OnAirClockTests {
    @Test func zeroAndUnusableInputsAreZero() {
        #expect(OnAirClock.format(0) == "00:00")
        #expect(OnAirClock.format(-4) == "00:00")
        #expect(OnAirClock.format(.nan) == "00:00")
        #expect(OnAirClock.format(.infinity) == "00:00")
        #expect(OnAirClock.format(-.infinity) == "00:00")
    }

    @Test func truncatesTowardZeroAndRollsMinutes() {
        #expect(OnAirClock.format(59.9) == "00:59")
        #expect(OnAirClock.format(60) == "01:00")
        #expect(OnAirClock.format(83) == "01:23")
        #expect(OnAirClock.format(83.9) == "01:23")
        #expect(OnAirClock.format(3600) == "60:00")
    }

    @Test func capsAtNinetyNineMinutes() {
        #expect(OnAirClock.format(99 * 60 + 59) == "99:59")
        #expect(OnAirClock.format(100 * 60) == "99:59")
    }
}

@Suite("Look") struct OnAirLookTests {
    @Test func dimTracksTheThrowAndBottomsNearBlack() {
        #expect(OnAirTuning.dimAmount(progress: 0) == 0)
        #expect(OnAirTuning.backgroundMultiply(progress: 0) == 1)
        #expect(abs(OnAirTuning.backgroundMultiply(progress: 1) - OnAirTuning.dimFloor) < 1e-12)
        #expect(OnAirTuning.dimAmount(progress: 0.2) < OnAirTuning.dimAmount(progress: 0.8))
        #expect(OnAirTuning.backgroundMultiply(progress: 1) < 0.1)
    }

    @Test func chromeAndGlowFollowOneProgress() {
        #expect(OnAirTuning.chromeOpacity(progress: 0) == 0)
        #expect(OnAirTuning.chromeOpacity(progress: 1) == 1)
        #expect(OnAirTuning.glow(progress: 0, elapsed: 3, live: true, reduceMotion: false) == 0)
        #expect(OnAirTuning.glow(progress: 1, elapsed: 0, live: true, reduceMotion: false) == 1)
        let held = OnAirTuning.glow(progress: 0.7, elapsed: 0, live: false, reduceMotion: false)
        let later = OnAirTuning.glow(progress: 0.7, elapsed: 9, live: false, reduceMotion: false)
        #expect(held == later)
    }

    @Test func breathDipsAndReduceMotionHoldsStill() {
        let peak = OnAirTuning.breath(at: 0, reduceMotion: false)
        let trough = OnAirTuning.breath(at: OnAirTuning.breathPeriod / 2, reduceMotion: false)
        let again = OnAirTuning.breath(at: OnAirTuning.breathPeriod, reduceMotion: false)
        #expect(peak == 1)
        #expect(abs(trough - (1 - OnAirTuning.breathDepth)) < 1e-9)
        #expect(abs(again - 1) < 1e-9)
        #expect(OnAirTuning.breath(at: OnAirTuning.breathPeriod / 2, reduceMotion: true) == 1)
        #expect(OnAirTuning.breath(at: .nan, reduceMotion: false) == 1)
        let live = OnAirTuning.glow(progress: 1, elapsed: OnAirTuning.breathPeriod / 2, live: true, reduceMotion: false)
        let held = OnAirTuning.glow(progress: 1, elapsed: OnAirTuning.breathPeriod / 2, live: true, reduceMotion: true)
        #expect(abs(live - (1 - OnAirTuning.breathDepth)) < 1e-9)
        #expect(held == 1)
    }

    @Test func breathDoesNotDimTheRoom() {
        var live = OnAirModel()
        _ = live.setOn(true)
        live.run(OnAirTuning.breathPeriod / 2)
        #expect(abs(live.backgroundMultiply - OnAirTuning.dimFloor) < 1e-9)
        #expect(live.glow < 0.9)
        #expect(abs(live.dimAmount - OnAirTuning.dimAmount(progress: live.throwProgress)) < 1e-12)
        #expect(abs(live.chromeOpacity - OnAirTuning.chromeOpacity(progress: live.throwProgress)) < 1e-12)
    }

    @Test func meterIsBoundedAndStillUnderReduceMotion() {
        let moving = OnAirTuning.meterLevels(at: 1.2, reduceMotion: false)
        let again = OnAirTuning.meterLevels(at: 1.2, reduceMotion: false)
        let still = OnAirTuning.meterLevels(at: 1.2, reduceMotion: true)
        let stillLater = OnAirTuning.meterLevels(at: 9, reduceMotion: true)
        #expect(moving.count == OnAirTuning.meterCount)
        #expect(moving == again)
        #expect(still == stillLater)
        #expect(moving != still)
        for level in moving + still {
            #expect(level > 0 && level <= 1)
        }
        #expect(OnAirTuning.meterLevels(at: .nan, reduceMotion: false) == still)
    }

    @Test func knobTravelMatchesTheTrack() {
        let off = OnAirTuning.knobCenter(progress: 0)
        let on = OnAirTuning.knobCenter(progress: 1)
        #expect(abs(off.y - (OnAirTuning.pillY + OnAirTuning.pillHeight / 2)) < 1e-9)
        #expect(abs((on.x - off.x) - OnAirTuning.travel) < 1e-9)
        #expect(OnAirTuning.progress(forSceneX: off.x) == 0)
        #expect(abs(OnAirTuning.progress(forSceneX: on.x) - 1) < 1e-9)
        #expect(OnAirTuning.progress(forSceneX: .nan) == 0)
        #expect(OnAirTuning.progress(forSceneX: -100) == 0)
        #expect(OnAirTuning.progress(forSceneX: 9_000) == 1)
    }

    @Test func polynomialTrigMatchesTheEasyAngles() {
        #expect(OnAirMath.sin(0) == 0)
        #expect(abs(OnAirMath.sin(OnAirMath.halfPi) - 1) < 1e-12)
        #expect(abs(OnAirMath.cos(0) - 1) < 1e-12)
        #expect(abs(OnAirMath.cos(OnAirMath.pi) + 1) < 1e-12)
        #expect(OnAirMath.sin(.nan) == 0)
        #expect(OnAirMath.sin(.infinity) == 0)
    }
}

@Suite("Throw") struct OnAirThrowTests {
    @Test func aThrowOvershootsThenSeatsWithOneClick() {
        var model = OnAirModel()
        let began = model.setOn(true)
        #expect(committed(began) == [true])
        #expect(haptics(began) == 0)
        var peak = 0.0
        var clicks = 0
        var progressAtClick = -1.0
        for _ in 0..<120 {
            let events = model.step(1.0 / 60)
            if haptics(events) > 0, progressAtClick < 0 { progressAtClick = model.throwProgress }
            clicks += haptics(events)
            peak = max(peak, model.throwProgress)
        }
        #expect(peak > 1.01)
        #expect(progressAtClick >= 1)
        #expect(model.throwProgress == 1)
        #expect(model.spring.velocity == 0)
        #expect(clicks == 1)
        #expect(model.isOn)
    }

    @Test func theClickIsNotRepeatedWhileTheClockRuns() {
        var model = OnAirModel()
        _ = model.setOn(true)
        let events = model.run(4.05)
        #expect(haptics(events) == 1)
        #expect(model.timerText == "00:04")
        #expect(model.accessibilityValue == "On air, 00:04")
        let again = model.setOn(true)
        #expect(again.isEmpty)
        let later = model.run(1)
        #expect(haptics(later) == 0)
    }

    @Test func theTimerCountsOnlyWhileOnAndResetsAfterTheReturn() {
        var model = OnAirModel()
        _ = model.setOn(true)
        // A hair past 83 s, so truncating to mm:ss still reads 01:23.
        for _ in 0..<(83 * 60 + 30) { _ = model.step(1.0 / 60) }
        #expect(model.timerText == "01:23")
        #expect(model.accessibilityValue == "On air, 01:23")
        let leaving = model.setOn(false)
        #expect(committed(leaving) == [false])
        #expect(model.timerText == "01:23")
        _ = model.step(1.0 / 60)
        #expect(model.elapsed > 80)
        let events = model.run(2)
        #expect(haptics(events) == 1)
        #expect(model.throwProgress == 0)
        #expect(model.elapsed == 0)
        #expect(model.timerText == "00:00")
        #expect(model.accessibilityValue == "Off")
        #expect(!model.needsClock)
    }

    @Test func aLargeFrameStaysFiniteAndDoesNotSkipTheClock() {
        var model = OnAirModel()
        _ = model.setOn(true)
        _ = model.step(10)
        #expect(model.throwProgress.isFinite)
        #expect(model.spring.velocity.isFinite)
        #expect(model.elapsed == WhimsySpring.maxFrame)
        let zero = model.step(0)
        let backward = model.step(-1)
        let bad = model.step(.nan)
        #expect(zero.isEmpty)
        #expect(backward.isEmpty)
        #expect(bad.isEmpty)
        #expect(model.elapsed == WhimsySpring.maxFrame)
    }

    @Test func draggingFollowsTheFingerAndDoesNotIntegrate() {
        var model = OnAirModel()
        let y = pillMidY
        let missed = model.beginDrag(sceneX: 10, sceneY: 10)
        let bad = model.beginDrag(sceneX: .nan, sceneY: y)
        #expect(!missed)
        #expect(!bad)
        #expect(!model.isDragging)
        let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.25), sceneY: y)
        #expect(grabbed)
        #expect(abs(model.throwProgress - 0.25) < 1e-9)
        #expect(model.spring.velocity == 0)
        model.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.4))
        let held = model.throwProgress
        _ = model.step(0.05)
        #expect(model.throwProgress == held)
        #expect(model.isDragging)
        model.updateDrag(sceneX: .nan)
        #expect(model.throwProgress == held)
    }

    @Test func releaseBelowTheThresholdThrowsHome() {
        var model = OnAirModel()
        let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.2), sceneY: pillMidY)
        #expect(grabbed)
        model.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.49))
        let events = model.endDrag(translation: 40)
        #expect(committed(events).isEmpty)
        #expect(!model.isOn)
        #expect(!model.isDragging)
        let rest = model.run(1.5)
        #expect(haptics(rest) == 1)
        #expect(model.throwProgress == 0)
        #expect(model.accessibilityValue == "Off")
    }

    @Test func releaseOnTheThresholdCommits() {
        var below = OnAirModel()
        let grabbedLow = below.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0), sceneY: pillMidY)
        #expect(grabbedLow)
        below.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.49))
        let belowEvents = below.endDrag(translation: 30)
        #expect(committed(belowEvents).isEmpty)

        var onTheLine = OnAirModel()
        let grabbedLine = onTheLine.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0), sceneY: pillMidY)
        #expect(grabbedLine)
        onTheLine.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.5))
        let events = onTheLine.endDrag(translation: 30)
        #expect(committed(events) == [true])
        #expect(onTheLine.isOn)
        #expect(onTheLine.accessibilityValue == "On air, 00:00")
        let rest = onTheLine.run(1.5)
        #expect(haptics(rest) == 1)
        #expect(onTheLine.throwProgress == 1)
    }

    @Test func aShortReleaseTogglesInsteadOfCommittingTheFinger() {
        var model = OnAirModel()
        let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.9), sceneY: pillMidY)
        #expect(grabbed)
        let events = model.endDrag(translation: OnAirTuning.tapSlop)
        #expect(committed(events) == [true])
        #expect(model.throwProgress < 0.05)
        #expect(haptics(events) == 0)
        _ = model.run(1.5)
        #expect(model.isOn)
        #expect(model.throwProgress == 1)
    }

    @Test func endDragWithoutAGrabDoesNothing() {
        var model = OnAirModel()
        let events = model.endDrag(translation: 40)
        #expect(events.isEmpty)
        #expect(!model.isOn)
    }

    @Test func aNonFiniteReleaseReturnsToTheDetent() {
        var model = OnAirModel()
        _ = model.setOn(true)
        _ = model.run(1.5)
        let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.2), sceneY: pillMidY)
        #expect(grabbed)
        let events = model.endDrag(translation: .nan)
        #expect(committed(events).isEmpty)
        #expect(model.isOn)
        _ = model.run(1.5)
        #expect(model.throwProgress == 1)
        let quiet = model.run(0.2)
        #expect(haptics(quiet) == 0)
    }

    @Test func grabbingCancelsTheInFlightClick() {
        var model = OnAirModel()
        _ = model.setOn(true)
        _ = model.step(0.05)
        let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.15), sceneY: pillMidY)
        #expect(grabbed)
        model.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.1))
        let events = model.endDrag(translation: 36)
        #expect(committed(events) == [false])
        let rest = model.run(1.5)
        #expect(haptics(rest) == 1)
        #expect(model.throwProgress == 0)
    }
}

@Suite("Reduce motion") struct OnAirReduceMotionTests {
    @Test func theCrossfadeReplacesTheSpring() {
        var model = OnAirModel(reduceMotion: true)
        let began = model.setOn(true)
        #expect(haptics(began) == 0)
        var peak = 0.0
        var clicks = 0
        var clickedAt = -1.0
        for i in 0..<40 {
            let events = model.step(1.0 / 60)
            peak = max(peak, model.throwProgress)
            if haptics(events) > 0 { clickedAt = Double(i) / 60 }
            clicks += haptics(events)
        }
        #expect(peak <= 1 + 1e-9)
        #expect(model.throwProgress == 1)
        #expect(clicks == 1)
        #expect(clickedAt >= OnAirTuning.reduceDuration - 1.0 / 60)
        #expect(clickedAt < OnAirTuning.reduceDuration + 1.0 / 60)
        #expect(model.glow == 1)
        model.run(OnAirTuning.breathPeriod / 2)
        #expect(model.glow == 1)
        #expect(model.meter == OnAirTuning.meterLevels(at: model.elapsed, reduceMotion: true))
    }

    @Test func reversingMidFadeClicksOnce() {
        var model = OnAirModel(reduceMotion: true)
        _ = model.setOn(true)
        _ = model.step(0.1)
        let back = model.setOn(false)
        #expect(haptics(back) == 0)
        #expect(!model.isOn)
        let events = model.run(1)
        #expect(haptics(events) == 1)
        #expect(model.throwProgress == 0)
        #expect(model.elapsed == 0)
    }

    @Test func switchingMotionHandsTheThrowOver() {
        var model = OnAirModel()
        _ = model.setOn(true)
        _ = model.step(0.08)
        let mid = model.throwProgress
        #expect(mid > 0.05 && mid < 0.95)
        model.setReduceMotion(true)
        var peak = mid
        let events = model.run(0.6)
        peak = max(peak, model.throwProgress)
        #expect(peak <= 1 + 1e-9)
        #expect(haptics(events) == 1)
        #expect(model.throwProgress == 1)
        model.setReduceMotion(false)
        _ = model.setOn(false)
        let back = model.run(1.5)
        #expect(haptics(back) == 1)
        #expect(model.throwProgress == 0)
    }

    @Test func settingTheSameFlagDoesNothing() {
        var model = OnAirModel(reduceMotion: true)
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        #expect(model.throwProgress == 0)
    }
}
