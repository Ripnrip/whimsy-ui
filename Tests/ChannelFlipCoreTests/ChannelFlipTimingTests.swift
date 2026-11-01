import Testing
import Foundation
@testable import ChannelFlipCore

@Suite struct EnvelopeTests {
    @Test func zeroAtBothEndsAndOutside() {
        #expect(ChannelFlipTiming.envelope(0) == 0)
        #expect(ChannelFlipTiming.envelope(1) == 0)
        #expect(ChannelFlipTiming.envelope(-0.3) == 0)
        #expect(ChannelFlipTiming.envelope(1.7) == 0)
        #expect(ChannelFlipTiming.envelope(.nan) == 0)
    }

    @Test func peaksAtOneInTheMiddle() {
        #expect(ChannelFlipTiming.envelope(ChannelFlipTiming.swapProgress) == 1)
        for i in 1..<100 where i != 50 { #expect(ChannelFlipTiming.envelope(Double(i) / 100) < 1) }
    }

    @Test func risesThenFalls() {
        var prev = 0.0
        for i in 1...50 {
            let e = ChannelFlipTiming.envelope(Double(i) / 100)
            #expect(e >= prev); prev = e
        }
        for i in 51..<100 {
            let e = ChannelFlipTiming.envelope(Double(i) / 100)
            #expect(e <= prev); prev = e
        }
    }

    @Test func isSymmetric() {
        for i in 1..<50 {
            let a = ChannelFlipTiming.envelope(Double(i) / 100), b = ChannelFlipTiming.envelope(1 - Double(i) / 100)
            #expect(abs(a - b) < 1e-12)
        }
    }

    @Test func staysInUnitRange() {
        for i in -20...120 {
            let e = ChannelFlipTiming.envelope(Double(i) / 100)
            #expect(e >= 0 && e <= 1)
        }
    }
}

@Suite struct FrameQuantizationTests {
    @Test func frameCountIsOddAndAtLeastThree() {
        for d in stride(from: 0.0, through: 1.5, by: 0.01) {
            let n = ChannelFlipTiming.frameCount(duration: d)
            #expect(n >= 3 && n % 2 == 1)
        }
        #expect(ChannelFlipTiming.frameCount(duration: .nan) == 3)
        #expect(ChannelFlipTiming.frameCount(duration: -1) == 3)
    }

    @Test func aTapShowsAFewFrames() {
        #expect(ChannelFlipTiming.frameCount(duration: 0.35) == 5)
        #expect(ChannelFlipTiming.frameCount(duration: 0.7) == 11)
        #expect(ChannelFlipTiming.frameCount(duration: ChannelFlipTiming.reducedDuration) == 3)
    }

    @Test func longerTransitionsNeverShowFewerFrames() {
        var prev = 0
        for d in stride(from: 0.2, through: 0.8, by: 0.01) {
            let n = ChannelFlipTiming.frameCount(duration: d)
            #expect(n >= prev); prev = n
        }
    }

    @Test func frameIndexStepsThroughEveryFrameOnce() {
        let d = 0.35, n = ChannelFlipTiming.frameCount(duration: d)
        var seen: [Int] = []
        var t = 0.0
        while let f = ChannelFlipTiming.frameIndex(elapsed: t, duration: d) {
            if seen.last != f { seen.append(f) }
            t += 0.001
        }
        #expect(seen == Array(0..<n))
    }

    @Test func frameIndexIsHeldBetweenFrames() {
        let d = 0.35
        // The effect only changes 15 times a second, whatever the display rate.
        #expect(ChannelFlipTiming.frameIndex(elapsed: 0.001, duration: d) == ChannelFlipTiming.frameIndex(elapsed: 0.06, duration: d))
        #expect(ChannelFlipTiming.frameIndex(elapsed: 0.07, duration: d) == 1)
    }

    @Test func frameIndexIsNilWhenOverOrInvalid() {
        #expect(ChannelFlipTiming.frameIndex(elapsed: 0.35, duration: 0.35) == nil)
        #expect(ChannelFlipTiming.frameIndex(elapsed: 5, duration: 0.35) == nil)
        #expect(ChannelFlipTiming.frameIndex(elapsed: 0.1, duration: 0) == nil)
        #expect(ChannelFlipTiming.frameIndex(elapsed: .nan, duration: 0.35) == nil)
        #expect(ChannelFlipTiming.frameIndex(elapsed: -1, duration: 0.35) == 0)
    }

    @Test func quantizedProgressIsStrictlyInsideAndEvenlySpaced() {
        let n = 5
        let p = (0..<n).map { ChannelFlipTiming.quantizedProgress(frame: $0, count: n) }
        #expect(p.first! > 0 && p.last! < 1)
        for i in 1..<n { #expect(abs((p[i] - p[i - 1]) - 1.0 / Double(n + 1)) < 1e-12) }
    }

    @Test func everyFrameHasSomeIntensityBecauseNoneSitsAtTheEnds() {
        for d in [0.2, 0.35, 0.5, 0.7] {
            let n = ChannelFlipTiming.frameCount(duration: d)
            for f in 0..<n { #expect(ChannelFlipTiming.intensity(frame: f, count: n, strength: 1) > 0) }
        }
    }
}

@Suite struct SwapMomentTests {
    @Test func theMiddleFrameIsExactlyAtTheSwapProgressAndThePeak() {
        for d in [0.2, 0.35, 0.5, 0.7] {
            let n = ChannelFlipTiming.frameCount(duration: d)
            let f = ChannelFlipTiming.swapFrame(count: n)
            let p = ChannelFlipTiming.quantizedProgress(frame: f, count: n)
            #expect(p == ChannelFlipTiming.swapProgress)
            #expect(ChannelFlipTiming.envelope(p) == 1)
            // no other frame is as strong
            for g in 0..<n where g != f { #expect(ChannelFlipTiming.intensity(frame: g, count: n, strength: 1) < 1) }
        }
    }

    @Test func swapHappensOnAFrameBoundaryNearTheMiddle() {
        let d = 0.35
        var t = 0.0
        while !ChannelFlipTiming.hasSwapped(elapsed: t, duration: d) { t += 0.0005 }
        #expect(t > 0.2 * d && t < 0.8 * d)
        let n = ChannelFlipTiming.frameCount(duration: d)
        #expect(abs(t - Double(ChannelFlipTiming.swapFrame(count: n)) / Double(n) * d) < 0.002)
    }

    @Test func notSwappedAtTheStartAndSwappedAfterTheEnd() {
        #expect(!ChannelFlipTiming.hasSwapped(elapsed: 0, duration: 0.35))
        #expect(ChannelFlipTiming.hasSwapped(elapsed: 0.35, duration: 0.35))
        #expect(ChannelFlipTiming.hasSwapped(elapsed: 9, duration: 0.35))
    }

    @Test func swapCrossingIsDetectedOnceAcrossAnyStepSize() {
        for d in [0.35, 0.5, 0.7] {
            for step in [0.001, 0.008, 0.016, 0.033, 0.05, 0.2] {
                var t = 0.0, crossings = 0
                while t < d + step {
                    if ChannelFlipTiming.crossesSwap(from: t, to: t + step, duration: d) { crossings += 1 }
                    t += step
                }
                #expect(crossings == 1)
            }
        }
    }

    @Test func noCrossingWhenBothEndsOnTheSameSide() {
        #expect(!ChannelFlipTiming.crossesSwap(from: 0, to: 0.05, duration: 0.35))
        #expect(!ChannelFlipTiming.crossesSwap(from: 0.25, to: 0.34, duration: 0.35))
        #expect(!ChannelFlipTiming.crossesSwap(from: 0.4, to: 0.5, duration: 0.35))
    }
}

@Suite struct SeedTests {
    @Test func transitionSeedIsDeterministicAndBelow2To14() {
        for e in 0..<500 {
            let s = ChannelFlipTiming.transitionSeed(e)
            #expect(s == ChannelFlipTiming.transitionSeed(e) && s < 0x4000)
        }
        #expect(ChannelFlipTiming.transitionSeed(1) != ChannelFlipTiming.transitionSeed(2))
    }

    @Test func frameSeedIsNewEveryFrameAndExactInAFloat() {
        let t = ChannelFlipTiming.transitionSeed(3)
        let seeds = (0..<11).map { ChannelFlipTiming.frameSeed(transition: t, frame: $0) }
        #expect(Set(seeds).count == seeds.count)
        for s in seeds { #expect(Double(Float(s)) == s && s < 524_288) }
    }
}
