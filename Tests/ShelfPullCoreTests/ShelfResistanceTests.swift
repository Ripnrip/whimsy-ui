import Testing
import Foundation
@testable import ShelfPullCore

@Suite struct ShelfResistanceTests {
    static let heights: [Double] = [118, 130, 150, 170]

    @Test(arguments: heights)
    func startsOneToOne(_ h: Double) {
        let r = ShelfResistance.rise(forDrag: 0.5, height: h)
        #expect(abs(r - 0.5) < 0.5 * 0.5 / (0.7 * h) + 1e-9)
        #expect(abs(ShelfResistance.slope(atDrag: 0, height: h) - 1) < 1e-12)
    }

    @Test(arguments: heights)
    func neverReachesTheLimit(_ h: Double) {
        let limit = ShelfResistance.maxRise(height: h)
        for d in [10.0, 100, 1_000, 1e5, 1e9] { #expect(ShelfResistance.rise(forDrag: d, height: h) < limit) }
        #expect(ShelfResistance.rise(forDrag: 1e9, height: h) > limit * 0.999)
    }

    @Test(arguments: heights)
    func isIncreasingWithDiminishingReturns(_ h: Double) {
        var prevRise = 0.0, prevGain = Double.infinity
        for i in 1...200 {
            let r = ShelfResistance.rise(forDrag: Double(i) * 2, height: h)
            #expect(r > prevRise)
            let gain = r - prevRise
            #expect(gain < prevGain)
            prevGain = gain; prevRise = r
        }
    }

    @Test(arguments: heights)
    func slopeFallsAndMatchesTheCurve(_ h: Double) {
        var prev = 2.0
        for d in stride(from: 0.0, through: 400, by: 20) {
            let s = ShelfResistance.slope(atDrag: d, height: h)
            #expect(s < prev && s > 0)
            prev = s
            let eps = 1e-5
            let numeric = (ShelfResistance.rise(forDrag: d + eps, height: h) - ShelfResistance.rise(forDrag: max(d - eps, 0), height: h)) / (d == 0 ? eps : 2 * eps)
            #expect(abs(numeric - s) < 1e-3)
        }
    }

    @Test(arguments: heights)
    func inverseRoundTrips(_ h: Double) {
        for d in [0.5, 5, 20, 55, 100, 250, 900] {
            let r = ShelfResistance.rise(forDrag: d, height: h)
            #expect(abs(ShelfResistance.drag(forRise: r, height: h) - d) < 1e-6 * max(1, d))
        }
    }

    @Test func nonPositiveAndBadInputsGiveNoRise() {
        #expect(ShelfResistance.rise(forDrag: 0, height: 150) == 0)
        #expect(ShelfResistance.rise(forDrag: -40, height: 150) == 0)
        #expect(ShelfResistance.rise(forDrag: .nan, height: 150) == 0)
        #expect(ShelfResistance.rise(forDrag: -.infinity, height: 150) == 0)
        #expect(ShelfResistance.drag(forRise: -3, height: 150) == 0)
        #expect(ShelfResistance.drag(forRise: .nan, height: 150) == 0)
    }

    @Test func inverseClampsAtTheLimit() {
        let d = ShelfResistance.drag(forRise: 1_000, height: 150)
        #expect(d.isFinite && d > 1_000)
    }

    @Test func commitDistanceIs55PercentOfHeight() {
        #expect(abs(ShelfResistance.commitDistance(height: 160) - 88) < 1e-12)
        // at that pull the book has visibly risen about 31% of its height
        let r = ShelfResistance.rise(forDrag: 88, height: 160)
        #expect(abs(r / 160 - 0.308) < 0.001)
    }

    @Test func releaseAtTheThresholdCommits() {
        let h = 150.0, c = ShelfResistance.commitDistance(height: h)
        #expect(ShelfResistance.decide(drag: c, velocity: 0, height: h) == .commitDrag)
        #expect(ShelfResistance.decide(drag: c + 40, velocity: 0, height: h) == .commitDrag)
        #expect(ShelfResistance.decide(drag: c - 0.01, velocity: 0, height: h) == .springBack)
        #expect(ShelfResistance.decide(drag: c - 20, velocity: 100, height: h) == .springBack)
    }

    @Test func fastFlickCommitsBelowTheThreshold() {
        let h = 150.0
        #expect(ShelfResistance.decide(drag: 30, velocity: 900, height: h) == .commitFlick)
        #expect(ShelfResistance.decide(drag: 30, velocity: 2_500, height: h) == .commitFlick)
        #expect(ShelfResistance.decide(drag: 30, velocity: 899.9, height: h) == .springBack)
        #expect(ShelfResistance.decide(drag: 11.9, velocity: 5_000, height: h) == .springBack)
        #expect(ShelfResistance.decide(drag: 12, velocity: 5_000, height: h) == .commitFlick)
    }

    @Test func downwardOrBadVelocityNeverCommits() {
        #expect(ShelfResistance.decide(drag: 40, velocity: -3_000, height: 150) == .springBack)
        #expect(ShelfResistance.decide(drag: 40, velocity: .nan, height: 150) == .springBack)
        #expect(ShelfResistance.decide(drag: 40, velocity: .infinity, height: 150) == .springBack)
    }

    @Test func tinyPullsAreTaps() {
        #expect(ShelfResistance.decide(drag: 0, velocity: 5_000, height: 150) == .none)
        #expect(ShelfResistance.decide(drag: 0.4, velocity: 5_000, height: 150) == .none)
        #expect(ShelfResistance.decide(drag: -30, velocity: 5_000, height: 150) == .none)
        #expect(ShelfResistance.decide(drag: 3, velocity: 0, height: 150) == .springBack)
    }

    @Test func commitFlags() {
        #expect(ShelfRelease.commitDrag.commits && ShelfRelease.commitFlick.commits)
        #expect(!ShelfRelease.springBack.commits && !ShelfRelease.none.commits)
    }
}

@Suite struct ShelfVelocityTrackerTests {
    @Test func emptyIsZero() {
        #expect(ShelfVelocityTracker().velocity(at: 1) == 0)
        #expect(ShelfVelocityTracker().isEmpty)
    }

    @Test func steadyPullGivesItsSpeed() {
        var t = ShelfVelocityTracker()
        for i in 0...10 { t.add(upward: Double(i) * 5, at: Double(i) * 0.01) }
        #expect(abs(t.velocity(at: 0.1) - 500) < 1e-6)
    }

    @Test func onlyTheLastTenthOfASecondCounts() {
        var t = ShelfVelocityTracker()
        for i in 0...20 { t.add(upward: i < 10 ? 0 : Double(i - 10) * 20, at: Double(i) * 0.01) }
        // the last 0.1 s moved 200 pt in 0.1 s
        #expect(abs(t.velocity(at: 0.2) - 2_000) < 1e-6)
    }

    @Test func aFingerThatStoppedIsSlow() {
        var t = ShelfVelocityTracker()
        for i in 0...10 { t.add(upward: Double(i) * 10, at: Double(i) * 0.01) }
        #expect(t.velocity(at: 0.1) > 900)
        #expect(t.velocity(at: 0.1 + 0.061) == 0)
        #expect(t.velocity(at: 0.1 + 0.05) > 900)
    }

    @Test func downwardMotionIsNegative() {
        var t = ShelfVelocityTracker()
        for i in 0...5 { t.add(upward: 50 - Double(i) * 10, at: Double(i) * 0.01) }
        #expect(t.velocity(at: 0.05) < 0)
    }

    @Test func oneSampleAndSameTimeSamplesGiveZero() {
        var t = ShelfVelocityTracker()
        t.add(upward: 10, at: 1)
        #expect(t.velocity(at: 1) == 0)
        t.add(upward: 20, at: 1)
        #expect(t.velocity(at: 1) == 0)
    }

    @Test func ignoresBadAndOutOfOrderSamples() {
        var t = ShelfVelocityTracker()
        t.add(upward: .nan, at: 0); t.add(upward: 5, at: .infinity)
        #expect(t.isEmpty)
        t.add(upward: 0, at: 1); t.add(upward: 10, at: 0.5); t.add(upward: 5, at: 1.05)
        #expect(abs(t.velocity(at: 1.05) - 100) < 1e-6)
    }

    @Test func resetForgetsEverything() {
        var t = ShelfVelocityTracker()
        t.add(upward: 0, at: 0); t.add(upward: 100, at: 0.05)
        t.reset()
        #expect(t.isEmpty && t.velocity(at: 0.05) == 0)
    }

    @Test func oldSamplesAreDropped() {
        var t = ShelfVelocityTracker()
        for i in 0...100 { t.add(upward: Double(i), at: Double(i) * 0.01) }
        #expect(abs(t.velocity(at: 1) - 100) < 1e-6)
    }
}
