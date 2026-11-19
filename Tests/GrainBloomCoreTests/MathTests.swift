import Testing
@testable import GrainBloomCore

@Suite("Grain bloom math") struct GrainBloomMathTests {
    @Test func bayer4MatchesTheConventionalMatrix() {
        let expected = [
            0, 8, 2, 10,
            12, 4, 14, 6,
            3, 11, 1, 9,
            15, 7, 13, 5,
        ]
        var index = 0
        for row in 0..<4 {
            for column in 0..<4 {
                #expect(GrainBloomMath.bayer4(row: row, column: column) == expected[index])
                index += 1
            }
        }
    }

    @Test func bayer8HoldsEachThresholdOnce() {
        var seen = Set<Int>()
        for row in 0..<8 {
            for column in 0..<8 {
                seen.insert(GrainBloomMath.bayer8(row: row, column: column))
            }
        }
        #expect(seen.count == 64)
        #expect(seen.contains(0))
        #expect(seen.contains(63))
    }

    @Test func grainIsDeterministicAndSeeded() {
        let first = GrainBloomMath.grain(x: 3, y: 9, frame: 2, seed: 11)
        let again = GrainBloomMath.grain(x: 3, y: 9, frame: 2, seed: 11)
        let other = GrainBloomMath.grain(x: 3, y: 9, frame: 2, seed: 12)
        #expect(first == again)
        #expect(first != other)
    }

    @Test func coverageIsMonotonicAndFinishesFull() {
        let start = GrainBloomMath.coverage(progress: 0)
        let mid = GrainBloomMath.coverage(progress: 0.5)
        let end = GrainBloomMath.coverage(progress: 1)
        #expect(start < 1)
        #expect(mid >= start)
        #expect(end == 1)
        var previous = -1.0
        for step in 0...8 {
            let sample = GrainBloomMath.coverage(progress: Double(step) / 8)
            #expect(sample >= previous)
            previous = sample
        }
    }

    @Test func lowThresholdRevealsBeforeHighThreshold() {
        let easy = point(threshold: 0)
        let hard = point(threshold: 63)
        #expect(GrainBloomMath.isRevealed(x: easy.x, y: easy.y, progress: 0.05))
        #expect(!GrainBloomMath.isRevealed(x: hard.x, y: hard.y, progress: 0.05))
        #expect(GrainBloomMath.isRevealed(x: hard.x, y: hard.y, progress: 1))
    }

    @Test func coarseRevealStaysWhenTheCellShrinks() {
        let sample = point(threshold: 0)
        #expect(GrainBloomMath.isRevealed(x: sample.x, y: sample.y, progress: 0.2))
        #expect(GrainBloomMath.cellSize(for: 0.2) == 8)
        #expect(GrainBloomMath.isRevealed(x: sample.x, y: sample.y, progress: 1))
        #expect(GrainBloomMath.cellSize(for: 1) == 1)
    }

    @Test func cellSizeStepsDownAndNeverIncreases() {
        let samples = [0.0, 0.1, 0.3, 0.5, 0.7, 0.95, 1.0]
        let sizes = samples.map { GrainBloomMath.cellSize(for: $0) }
        #expect(sizes[0] == 16)
        #expect(sizes.last == 1)
        for index in 1..<sizes.count {
            #expect(sizes[index] <= sizes[index - 1])
        }
    }

    @Test func rippleStartsAtTheCenter() {
        let center = GrainBloomMath.rippleDelay(
            x: GrainBloomTuning.stageWidth / 2,
            y: GrainBloomTuning.stageHeight / 2
        )
        let edge = GrainBloomMath.rippleDelay(x: GrainBloomTuning.stageWidth / 2, y: 0)
        let corner = GrainBloomMath.rippleDelay(x: 0, y: 0)
        #expect(center == 0)
        #expect(corner > edge)
    }

    @Test func blobsDriftUnlessReduceMotionFreezesThem() {
        let start = GrainBloomMath.blob(index: 1, time: 0, reduceMotion: false)
        let later = GrainBloomMath.blob(index: 1, time: 1.2, reduceMotion: false)
        let frozen = GrainBloomMath.blob(index: 1, time: 1.2, reduceMotion: true)
        #expect(start.x != later.x || start.y != later.y)
        #expect(frozen.x == start.x)
        #expect(frozen.y == start.y)
    }

    @Test func shimmerBlurAndGlintFollowTheTimeline() {
        #expect(GrainBloomMath.shimmer(phaseIsWaking: true, phaseTime: 0, reduceMotion: false) == 0)
        #expect(GrainBloomMath.shimmer(phaseIsWaking: true, phaseTime: GrainBloomTuning.wakeDuration, reduceMotion: false) == 1)
        #expect(GrainBloomMath.shimmer(phaseIsWaking: true, phaseTime: 0.4, reduceMotion: true) == 0)
        #expect(GrainBloomMath.blur(progress: 1, reduceMotion: false) == 0)
        #expect(GrainBloomMath.glint(playsSettle: false, phaseTime: 0.1, reduceMotion: false) == 0)
        let mid = GrainBloomMath.glint(
            playsSettle: true,
            phaseTime: GrainBloomTuning.settleDuration / 2,
            reduceMotion: false
        )
        #expect(mid > 0)
    }

    @Test func reduceMotionFreezesDotPulseAtTimeZero() {
        let delay = GrainBloomMath.rippleDelay(x: 40, y: 40)
        let origin = GrainBloomMath.dotScale(wakeTime: 0, delay: delay, reduceMotion: false)
        let later = GrainBloomMath.dotScale(wakeTime: 0.8, delay: delay, reduceMotion: true)
        let bright = GrainBloomMath.dotBrightness(wakeTime: 0.8, delay: delay, reduceMotion: true)
        let brightOrigin = GrainBloomMath.dotBrightness(wakeTime: 0, delay: delay, reduceMotion: false)
        #expect(later == origin)
        #expect(bright == brightOrigin)
    }

    @Test func paletteClampsEmptyAndLongInputs() {
        #expect(GrainBloomMath.normalizedPalette([]).count == 4)
        let five = (0..<5).map { GrainBloomRGB(r: Double($0), g: 0, b: 0) }
        let kept = GrainBloomMath.normalizedPalette(five)
        #expect(kept.count == 4)
        #expect(kept[0].r == 0)
        #expect(kept[3].r == 1)
    }

    private func point(threshold: Int) -> (x: Double, y: Double) {
        let size = 16.0
        for row in 0..<8 {
            for column in 0..<8 {
                if GrainBloomMath.bayer8(row: row, column: column) == threshold {
                    return (x: (Double(column) + 0.5) * size, y: (Double(row) + 0.5) * size)
                }
            }
        }
        return (8, 8)
    }
}
