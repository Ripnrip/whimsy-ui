import Foundation
import Testing
@testable import SlatSyncCore

@Suite("Optics") struct SlatOpticsTests {
    @Test func elevenReedsStayPut() {
        let first = (0..<11).map { SlatSyncMath.optics(index: $0) }
        let second = (0..<11).map { SlatSyncMath.optics(index: $0) }
        #expect(first == second)
        #expect(Set(first.map(\.index)).count == 11)
    }

    @Test func centreIsTheSharpestSlat() {
        let centre = SlatSyncMath.optics(index: 5)
        let top = SlatSyncMath.optics(index: 0)
        let bottom = SlatSyncMath.optics(index: 10)
        #expect(centre.blur < top.blur)
        #expect(centre.blur < bottom.blur)
        #expect(abs(centre.offsetX) < abs(top.offsetX))
        #expect(abs(centre.tilt) < abs(bottom.tilt))
    }

    @Test func theReedsStaySlight() {
        for index in 0..<11 {
            let optics = SlatSyncMath.optics(index: index)
            #expect(optics.blur > 2 && optics.blur < 20)
            #expect(abs(optics.offsetX) < 24)
            #expect(abs(optics.tilt) < 6)
        }
    }

    @Test func anIndexOutsideTheStackIsDark() {
        let optics = SlatSyncMath.optics(index: 11)
        #expect(optics.blur == 0 && optics.offsetX == 0 && optics.tilt == 0)
        #expect(SlatSyncMath.spread(index: -1, progress: 1) == 0)
        #expect(SlatSyncMath.spread(index: 11, progress: 1) == 0)
    }
}

@Suite("Spread") struct SlatSpreadTests {
    @Test func restLightsOnlyTheMiddleFive() {
        for index in 0..<11 {
            let spread = SlatSyncMath.spread(index: index, progress: 0)
            let distance = abs(index - 5)
            if distance <= SlatSyncTuning.coreRadius {
                #expect(spread > 0.08)
            } else {
                #expect(spread == 0)
            }
        }
        let centre = SlatSyncMath.spread(index: 5, progress: 0)
        #expect(centre > SlatSyncMath.spread(index: 3, progress: 0))
        #expect(centre < 0.3)
    }

    @Test func fullProgressFillsEverySlat() {
        for index in 0..<11 {
            let spread = SlatSyncMath.spread(index: index, progress: 1)
            #expect(spread > 0.95)
        }
        #expect(SlatSyncMath.spread(index: 5, progress: 1) == 1)
        #expect(SlatSyncMath.spread(index: 5, progress: 1) >= SlatSyncMath.spread(index: 0, progress: 1))
    }

    @Test func spreadGrowsAndNeverOvershoots() {
        for index in 0..<11 {
            var previous = -1.0
            for step in 0...20 {
                let spread = SlatSyncMath.spread(index: index, progress: Double(step) / 20)
                #expect(spread >= previous - 1e-12)
                #expect(spread >= 0 && spread <= 1)
                previous = spread
            }
        }
    }

    @Test func aBadProgressIsDark() {
        #expect(SlatSyncMath.spread(index: 5, progress: .nan) == 0)
        #expect(SlatSyncMath.spread(index: 5, progress: -.infinity) == 0)
        #expect(SlatSyncMath.spread(index: 5, progress: -0.4) == SlatSyncMath.spread(index: 5, progress: 0))
        #expect(SlatSyncMath.spread(index: 5, progress: 3) == SlatSyncMath.spread(index: 5, progress: 1))
    }
}

@Suite("Percent") struct SlatPercentTests {
    @Test func roundingBoundaries() {
        #expect(SlatSyncMath.percent(for: 0) == 0)
        #expect(SlatSyncMath.percent(for: 0.004) == 0)
        #expect(SlatSyncMath.percent(for: 0.005) == 1)
        #expect(SlatSyncMath.percent(for: 0.994) == 99)
        #expect(SlatSyncMath.percent(for: 0.995) == 100)
        #expect(SlatSyncMath.percent(for: 1) == 100)
        #expect(SlatSyncMath.percent(for: 1.4) == 100)
        #expect(SlatSyncMath.percent(for: -0.2) == 0)
        #expect(SlatSyncMath.percent(for: .nan) == 0)
        #expect(SlatSyncMath.percent(for: .infinity) == 0)
    }

    @Test func fortyTwoPercentReadsTheExample() {
        #expect(SlatSyncMath.percent(for: 0.42) == 42)
        #expect(SlatSyncMath.voiceOver(percent: 42) == "Syncing, 42 percent")
        #expect(SlatSyncMath.label(for: 42) == .syncing)
    }

    @Test func oneHundredFlipsTheLabel() {
        #expect(SlatSyncMath.label(for: 99) == .syncing)
        #expect(SlatSyncMath.label(for: 100) == .synced)
        #expect(SlatSyncMath.voiceOver(percent: 100) == "All synced")
        #expect(SlatSyncMath.voiceOver(percent: 0) == "Syncing, 0 percent")
    }
}

@Suite("Haptic") struct SlatHapticTests {
    @Test func oneCrossingFiresOnce() {
        var monitor = SlatSyncMonitor()
        #expect(monitor.setProgress(0.2) == false)
        #expect(monitor.setProgress(0.994) == false)
        #expect(monitor.setProgress(0.995) == true)
        #expect(monitor.setProgress(1) == false)
        #expect(monitor.setProgress(1) == false)
        #expect(monitor.hapticCount == 1)
    }

    @Test func aJumpToTheEndIsStillOneEvent() {
        var monitor = SlatSyncMonitor()
        #expect(monitor.setProgress(1.4) == true)
        #expect(monitor.setProgress(2) == false)
        #expect(monitor.hapticCount == 1)
        #expect(monitor.progress == 1)
    }

    @Test func droppingBelowRearms() {
        var monitor = SlatSyncMonitor(progress: 1)
        #expect(monitor.hapticCount == 0)
        #expect(monitor.setProgress(0.4) == false)
        #expect(monitor.setProgress(1) == true)
        #expect(monitor.hapticCount == 1)
    }

    @Test func nonFiniteInputDoesNothing() {
        var monitor = SlatSyncMonitor(progress: 0.4)
        #expect(monitor.setProgress(.nan) == false)
        #expect(monitor.progress == 0.4)
        #expect(monitor.hapticCount == 0)
        #expect(SlatSyncMath.crossedHundred(from: 0.2, to: .nan) == false)
        #expect(SlatSyncMath.crossedHundred(from: 1, to: 0.5) == false)
    }
}

@Suite("Wobble") struct SlatWobbleTests {
    @Test func reduceMotionAndBadAttitudeStayStill() {
        for index in 0..<11 {
            let reduced = SlatSyncMath.wobble(index: index, roll: 0.4, pitch: 0.3, reduceMotion: true)
            #expect(reduced == .zero)
            let broken = SlatSyncMath.wobble(index: index, roll: .nan, pitch: 0.2, reduceMotion: false)
            #expect(broken == .zero)
        }
        #expect(SlatSyncMath.wobble(index: 12, roll: 0.2, pitch: 0.2, reduceMotion: false) == .zero)
    }

    @Test func rollSlidesTheEndsFartherAndTheSameWay() {
        let centre = SlatSyncMath.wobble(index: 5, roll: 0.2, pitch: 0, reduceMotion: false)
        let top = SlatSyncMath.wobble(index: 0, roll: 0.2, pitch: 0, reduceMotion: false)
        let bottom = SlatSyncMath.wobble(index: 10, roll: 0.2, pitch: 0, reduceMotion: false)
        #expect(centre.offsetX > 0)
        #expect(top.offsetX > centre.offsetX)
        #expect(bottom.offsetX > centre.offsetX)
        #expect(abs(top.offsetX - bottom.offsetX) < 1e-9)
        let left = SlatSyncMath.wobble(index: 0, roll: -0.2, pitch: 0, reduceMotion: false)
        #expect(left.offsetX < 0)
    }

    @Test func pitchBowsTheStack() {
        let top = SlatSyncMath.wobble(index: 0, roll: 0, pitch: 0.25, reduceMotion: false)
        let bottom = SlatSyncMath.wobble(index: 10, roll: 0, pitch: 0.25, reduceMotion: false)
        let centre = SlatSyncMath.wobble(index: 5, roll: 0, pitch: 0.25, reduceMotion: false)
        #expect(top.tilt > 0)
        #expect(bottom.tilt < 0)
        #expect(centre.tilt == 0)
        #expect(abs(top.tilt + bottom.tilt) < 1e-9)
    }

    @Test func aWildAttitudeStopsAtTheClamp() {
        let wild = SlatSyncMath.wobble(index: 0, roll: 4, pitch: -4, reduceMotion: false)
        let clamped = SlatSyncMath.wobble(index: 0, roll: SlatSyncTuning.maxAttitude,
                                          pitch: -SlatSyncTuning.maxAttitude, reduceMotion: false)
        #expect(wild == clamped)
    }
}

@Suite("Scene") struct SlatSceneTests {
    @Test func elevenBandsStackDownThePage() {
        let scene = SlatSyncScene.make(progress: 0.42)
        #expect(scene.bands.count == 11)
        #expect(scene.percent == 42)
        #expect(scene.voiceOver == "Syncing, 42 percent")
        #expect(scene.opacity == 1)
        var previousY = -1.0
        for band in scene.bands {
            #expect(band.y > previousY)
            #expect(band.x > 0 && band.x + band.width < SlatSyncTuning.canvasWidth)
            #expect(band.height == SlatSyncTuning.slatHeight)
            previousY = band.y
        }
    }

    @Test func reduceMotionFadesTheFinishedAurora() {
        let scene = SlatSyncScene.make(progress: 0.4, roll: 0.3, pitch: 0.2, reduceMotion: true)
        #expect(scene.opacity == 0.4)
        #expect(scene.percent == 40)
        let full = SlatSyncScene.make(progress: 1)
        for (faded, done) in zip(scene.bands, full.bands) {
            #expect(abs(faded.spread - done.spread) < 1e-12)
            #expect(faded.opacity == 0.4)
            #expect(abs(faded.offsetX - SlatSyncMath.optics(index: faded.index).offsetX) < 1e-12)
            #expect(abs(faded.tilt - SlatSyncMath.optics(index: faded.index).tilt) < 1e-12)
        }
    }

    @Test func colourRunsFromCobaltToLime() {
        let top = SlatSyncMath.color(index: 0)
        let bottom = SlatSyncMath.color(index: 10)
        #expect(top == SlatSyncTuning.cobalt)
        #expect(bottom == SlatSyncTuning.lime)
        let middle = SlatSyncMath.color(index: 5)
        #expect(abs(middle.green - SlatSyncTuning.teal.green) < 0.08)
        #expect(middle.blue > bottom.blue)
    }
}

@Suite("Demo") struct SlatDemoTests {
    @Test func theCurveHoldsThenFinishes() {
        #expect(SlatSyncMath.demoProgress(at: 0) == 0)
        #expect(SlatSyncMath.demoProgress(at: SlatSyncTuning.demoDelay) == 0)
        #expect(SlatSyncMath.demoProgress(at: .nan) == 0)
        let mid = SlatSyncTuning.demoDelay + SlatSyncTuning.demoRun / 2
        #expect(abs(SlatSyncMath.demoProgress(at: mid) - 0.5) < 1e-12)
        let end = SlatSyncTuning.demoDelay + SlatSyncTuning.demoRun
        #expect(SlatSyncMath.demoProgress(at: end) == 1)
        #expect(SlatSyncMath.demoProgress(at: end + 2) == 1)
        #expect(SlatSyncMath.easeInOutCubic(0) == 0)
        #expect(SlatSyncMath.easeInOutCubic(1) == 1)
    }
}
