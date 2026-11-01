import Testing
import Foundation
@testable import ChannelFlipCore

private let size = Vec2(300, 420)
/// A picture with a different colour everywhere, so any displacement shows.
private func picture(_ p: Vec2) -> ChannelRGB {
    ChannelRGB(0.1 + 0.8 * (p.x / 300), 0.1 + 0.8 * (p.y / 420), 0.5 + 0.4 * sin(p.x / 23 + p.y / 31))
}

@Suite struct BandOffsetTests {
    @Test func isDeterministic() {
        for band in 0..<60 {
            #expect(ChannelFlipShading.bandOffset(band: band, seed: 1234, intensity: 0.8, width: 300)
                    == ChannelFlipShading.bandOffset(band: band, seed: 1234, intensity: 0.8, width: 300))
        }
    }

    @Test func zeroIntensityMeansNoTear() {
        for band in 0..<60 { #expect(ChannelFlipShading.bandOffset(band: band, seed: 7, intensity: 0, width: 300, forced: true) == 0) }
        #expect(ChannelFlipShading.bandOffset(band: 3, seed: 7, intensity: -1, width: 300) == 0)
        #expect(ChannelFlipShading.bandOffset(band: 3, seed: 7, intensity: .nan, width: 300) == 0)
    }

    @Test func neverExceedsTheMaximumShift() {
        for seed in stride(from: 0.0, to: 400, by: 7) {
            for band in 0..<60 {
                let o = ChannelFlipShading.bandOffset(band: band, seed: seed, intensity: 1, width: 300)
                #expect(abs(o) <= ChannelFlipShading.maxShift * 300 + 1e-9)
            }
        }
    }

    @Test func scalesWithIntensity() {
        // With the same hash, a stronger frame can only move a band further (when it tears at both strengths).
        var compared = 0
        for band in 0..<200 {
            let lo = ChannelFlipShading.bandOffset(band: band, seed: 99, intensity: 0.4, width: 300)
            let hi = ChannelFlipShading.bandOffset(band: band, seed: 99, intensity: 0.8, width: 300)
            if lo != 0 && hi != 0 { #expect(abs(hi) >= abs(lo) - 1e-9); compared += 1 }
        }
        #expect(compared > 20)
    }

    @Test func moreBandsTearAtHigherIntensity() {
        func torn(_ i: Double) -> Int { (0..<400).filter { ChannelFlipShading.bandOffset(band: $0, seed: 5, intensity: i, width: 300) != 0 }.count }
        #expect(torn(1) > torn(0.2))
        let frac = Double(torn(1)) / 400
        #expect(frac > 0.8 && frac < 0.97)   // 0.3 + 0.6, with hash noise
    }

    @Test func differentFramesTearDifferently() {
        let a = (0..<60).map { ChannelFlipShading.bandOffset(band: $0, seed: 100, intensity: 1, width: 300) }
        let b = (0..<60).map { ChannelFlipShading.bandOffset(band: $0, seed: 101, intensity: 1, width: 300) }
        #expect(a != b)
    }

    @Test func offsetsGoBothWays() {
        let o = (0..<200).map { ChannelFlipShading.bandOffset(band: $0, seed: 42, intensity: 1, width: 300) }
        #expect(o.contains { $0 > 10 } && o.contains { $0 < -10 })
    }

    @Test func forcedAlwaysTears() {
        let forced = (0..<100).filter { ChannelFlipShading.bandOffset(band: $0, seed: 8, intensity: 0.05, width: 300, forced: true) != 0 }.count
        let natural = (0..<100).filter { ChannelFlipShading.bandOffset(band: $0, seed: 8, intensity: 0.05, width: 300) != 0 }.count
        #expect(forced == 100 && forced > natural)
    }

    @Test func nonFiniteSeedIsSafe() {
        _ = ChannelFlipShading.bandOffset(band: 1, seed: .nan, intensity: 1, width: 300)
        _ = ChannelFlipShading.bandOffset(band: 1, seed: .infinity, intensity: 1, width: 300)
        #expect(ChannelFlipShading.bandOffset(band: 1, seed: .nan, intensity: 1, width: 300) == ChannelFlipShading.bandOffset(band: 1, seed: 0, intensity: 1, width: 300))
    }
}

@Suite struct SplitFlashTests {
    @Test func splitScalesWithIntensityAndWidth() {
        #expect(ChannelFlipShading.splitAmount(intensity: 0, width: 300) == 0)
        #expect(abs(ChannelFlipShading.splitAmount(intensity: 1, width: 300) - 12) < 1e-12)
        #expect(abs(ChannelFlipShading.splitAmount(intensity: 0.5, width: 300) - 6) < 1e-12)
        #expect(abs(ChannelFlipShading.splitAmount(intensity: 1, width: 600) - 24) < 1e-12)
    }

    @Test func flashRisesFasterThanLinearly() {
        #expect(ChannelFlipShading.flashAmount(intensity: 0) == 0)
        #expect(ChannelFlipShading.flashAmount(intensity: 1) == ChannelFlipShading.flash)
        #expect(ChannelFlipShading.flashAmount(intensity: 0.5) < 0.5 * ChannelFlipShading.flash)
    }

    @Test func scanlinesDimOddRowsOnly() {
        #expect(ChannelFlipShading.scanFactor(row: 4, intensity: 1) == 1)
        #expect(abs(ChannelFlipShading.scanFactor(row: 5, intensity: 1) - 0.88) < 1e-12)
        #expect(ChannelFlipShading.scanFactor(row: 5, intensity: 0) == 1)
    }

    @Test func wrapXKeepsXInsideTheCard() {
        #expect(ChannelFlipShading.wrapX(-10, width: 300) == 290)
        #expect(ChannelFlipShading.wrapX(310, width: 300) == 10)
        #expect(ChannelFlipShading.wrapX(150, width: 300) == 150)
        for x in stride(from: -700.0, through: 700, by: 13.7) {
            let w = ChannelFlipShading.wrapX(x, width: 300)
            #expect(w >= 0 && w < 300)
        }
    }

    @Test func barIsOnlyNearTheProgressRow() {
        #expect(ChannelFlipShading.bar(y: 210, progress: 0.5, height: 420) == 1)
        #expect(ChannelFlipShading.bar(y: 100, progress: 0.5, height: 420) == 0)
        let b = ChannelFlipShading.bar(y: 210 + 10, progress: 0.5, height: 420)
        #expect(b > 0 && b < 1)
    }
}

@Suite struct NoiseTests {
    @Test func isDeterministicAndInRange() {
        for i in 0..<200 {
            let v = ChannelFlipShading.noiseValue(cellX: i, cellY: i * 3, seed: 77)
            #expect(v == ChannelFlipShading.noiseValue(cellX: i, cellY: i * 3, seed: 77) && v >= 0 && v < 1)
        }
    }

    @Test func changesWithTheFrameSeed() {
        #expect(ChannelFlipShading.noiseValue(cellX: 4, cellY: 9, seed: 10) != ChannelFlipShading.noiseValue(cellX: 4, cellY: 9, seed: 11))
    }

    @Test func isRoughlyUniform() {
        var sum = 0.0, n = 0
        for x in 0..<80 { for y in 0..<80 { sum += ChannelFlipShading.noiseValue(cellX: x, cellY: y, seed: 3); n += 1 } }
        #expect(abs(sum / Double(n) - 0.5) < 0.02)
    }
}

@Suite struct ShadeTests {
    @Test func zeroIntensityLeavesThePictureAlone() {
        for (x, y) in [(0.5, 0.5), (12.3, 99.9), (150.0, 210.0), (299.5, 419.5)] {
            let p = Vec2(x, y)
            #expect(ChannelFlipShading.shade(at: p, size: size, progress: 0.3, intensity: 0, seed: 55, noiseAmount: 1, sample: picture) == picture(p))
        }
    }

    @Test func redAndBlueMoveApartAndGreenStays() {
        // Away from the bar and outside any tear, only the split shows.
        let p = Vec2(150, 30)
        let c = ChannelFlipShading.shade(at: p, size: size, progress: 0.9, intensity: 0.5, seed: 1, noiseAmount: 0, sample: { q in
            ChannelRGB(q.x / 300, q.x / 300, q.x / 300)
        })
        // Undo gain, scan and flash to compare the raw channels.
        let band = Int(floor(p.y / 7))
        let dx = ChannelFlipShading.bandOffset(band: band, seed: 1, intensity: 0.5, width: 300)
        let sp = ChannelFlipShading.splitAmount(intensity: 0.5, width: 300)
        let f = ChannelFlipShading.flashAmount(intensity: 0.5)
        let g = (1 + 0.3 * 0.5) * ChannelFlipShading.scanFactor(row: Int(floor(p.y / 2)), intensity: 0.5)
        func expected(_ x: Double) -> Double { let v = min(1, max(0, (x / 300) * g)); return v + (1 - v) * f }
        #expect(abs(c.r - expected(150 + dx - sp)) < 1e-9)
        #expect(abs(c.g - expected(150 + dx)) < 1e-9)
        #expect(abs(c.b - expected(150 + dx + sp)) < 1e-9)
        #expect(c.r < c.g && c.g < c.b)
    }

    @Test func rowsInOneBandMoveTogetherAndNeighbouringBandsCanDiffer() {
        // The sample position is recovered from the colour of a horizontal ramp; undo gain and scan first.
        func samplePos(y: Double) -> Double {
            let c = ChannelFlipShading.shade(at: Vec2(100, y), size: size, progress: 0.0, intensity: 1, seed: 9, noiseAmount: 0, sample: { q in ChannelRGB(q.x / 300, q.x / 300, q.x / 300) })
            return c.g
        }
        // all rows of band 10 (y 70..<77) read the same x once the per-row dimming is divided out
        func shifted(_ y: Double) -> Double {
            let g = 1.3 * ChannelFlipShading.scanFactor(row: Int(floor(y / 2)), intensity: 1)
            let f = ChannelFlipShading.flashAmount(intensity: 1)
            let v = samplePos(y: y)
            let raw = (v - f) / (1 - f)          // undo the flash mix
            return raw / g * 300
        }
        let rows = stride(from: 70.25, to: 77, by: 0.5).map(shifted)
        for r in rows { #expect(abs(r - rows[0]) < 1e-6) }
        let offsets = Set((0..<60).map { ChannelFlipShading.bandOffset(band: $0, seed: 9, intensity: 1, width: 300) })
        #expect(offsets.count > 20)
    }

    @Test func tearsWrapAroundTheEdges() {
        // Tear a band so far that its sample leaves the card: it must come back in from the other side.
        let c = ChannelFlipShading.shade(at: Vec2(2, 30), size: size, progress: 0.95, intensity: 1, seed: 3, noiseAmount: 0, sample: { q in
            #expect(q.x >= 0 && q.x < 300)
            return ChannelRGB(0.5, 0.5, 0.5)
        })
        #expect(c.r >= 0 && c.r <= 1)
    }

    @Test func outputStaysInRangeUnderFullBlast() {
        for seed in stride(from: 0.0, to: 80, by: 3) {
            for y in stride(from: 0.5, to: 420, by: 23.1) {
                for x in stride(from: 0.5, to: 300, by: 37.7) {
                    let c = ChannelFlipShading.shade(at: Vec2(x, y), size: size, progress: 0.5, intensity: 1, seed: seed, noiseAmount: 1, sample: picture)
                    #expect(c.r >= 0 && c.r <= 1 && c.g >= 0 && c.g <= 1 && c.b >= 0 && c.b <= 1)
                }
            }
        }
    }

    @Test func peakFrameBrightensAndFlashesTowardWhite() {
        func mean(_ i: Double) -> Double {
            var s = 0.0, n = 0.0
            for y in stride(from: 0.5, to: 420, by: 9.0) { for x in stride(from: 0.5, to: 300, by: 9.0) {
                let c = ChannelFlipShading.shade(at: Vec2(x, y), size: size, progress: 0.5, intensity: i, seed: 4, noiseAmount: 0, sample: { _ in ChannelRGB(0.4, 0.4, 0.4) })
                s += (c.r + c.g + c.b) / 3; n += 1
            } }
            return s / n
        }
        #expect(abs(mean(0) - 0.4) < 1e-12)
        #expect(mean(0.5) > 0.4)
        #expect(mean(1) > mean(0.5) + 0.1)
    }

    @Test func noiseOnlyShowsWhenSwitchedOn() {
        // At y = 410 the bar (progress 0 → y = 0) is far away and the picture is flat, so only noise varies along x.
        func row(_ amount: Double) -> [Double] {
            stride(from: 1.0, to: 300, by: 4.0).map { x in
                ChannelFlipShading.shade(at: Vec2(x, 410), size: size, progress: 0, intensity: 0.6, seed: 12, noiseAmount: amount, sample: { _ in ChannelRGB(0.5, 0.5, 0.5) }).r
            }
        }
        #expect(Set(row(0)).count == 1)
        #expect(Set(row(1)).count > 20)
        let spread = row(1).max()! - row(1).min()!
        #expect(spread > 0.05 && spread < 0.6)
    }

    @Test func isDeterministicPerFrameAndChangesBetweenFrames() {
        func render(_ seed: Double) -> [Double] {
            stride(from: 0.5, to: 420, by: 21.0).map { y in ChannelFlipShading.shade(at: Vec2(120, y), size: size, progress: 0.4, intensity: 0.9, seed: seed, noiseAmount: 1, sample: picture).r }
        }
        #expect(render(500) == render(500))
        #expect(render(500) != render(501))
    }
}
