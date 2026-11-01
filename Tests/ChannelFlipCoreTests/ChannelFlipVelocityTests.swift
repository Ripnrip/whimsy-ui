import Testing
import Foundation
@testable import ChannelFlipCore

@Suite struct VelocityMappingTests {
    @Test func slowSwipeIsShortAndMild() {
        let s = FlipVelocity.spec(forSpeed: 0)
        #expect(s.duration == 0.35 && s.strength == FlipVelocity.minStrength)
        #expect(FlipVelocity.spec(forSpeed: FlipVelocity.slowSpeed) == s)
    }

    @Test func fastFlickIsLongAndStrongAndClamped() {
        let s = FlipVelocity.spec(forSpeed: FlipVelocity.fastSpeed)
        #expect(s.duration == 0.7 && s.strength == 1)
        #expect(FlipVelocity.spec(forSpeed: 50_000) == s)
        #expect(FlipVelocity.spec(forSpeed: .infinity) == s)
    }

    @Test func signIsIgnored() {
        #expect(FlipVelocity.spec(forSpeed: -1200) == FlipVelocity.spec(forSpeed: 1200))
        #expect(FlipVelocity.spec(forSpeed: -.infinity) == FlipVelocity.spec(forSpeed: .infinity))
    }

    @Test func notANumberCountsAsSlow() {
        #expect(FlipVelocity.spec(forSpeed: .nan) == FlipVelocity.spec(forSpeed: 0))
    }

    @Test func growsMonotonicallyWithSpeed() {
        var prev = FlipVelocity.spec(forSpeed: 0)
        for v in stride(from: 0.0, through: 3000, by: 25) {
            let s = FlipVelocity.spec(forSpeed: v)
            #expect(s.duration >= prev.duration && s.strength >= prev.strength)
            prev = s
        }
    }

    @Test func stayInsideTheDocumentedRange() {
        for v in stride(from: -5000.0, through: 5000, by: 37) {
            let s = FlipVelocity.spec(forSpeed: v)
            #expect(s.duration >= 0.35 && s.duration <= 0.7)
            #expect(s.strength >= 0.45 && s.strength <= 1)
        }
    }

    @Test func midSpeedIsHalfway() {
        let mid = (FlipVelocity.slowSpeed + FlipVelocity.fastSpeed) / 2
        let s = FlipVelocity.spec(forSpeed: mid)
        #expect(abs(s.duration - 0.525) < 1e-12)
        #expect(abs(s.strength - 0.725) < 1e-12)
    }

    @Test func aTapSitsBetweenMildAndStrong() {
        let t = ChannelFlipTiming.tap
        #expect(t.duration == 0.35)
        #expect(t.strength > FlipVelocity.minStrength && t.strength < FlipVelocity.maxStrength)
    }
}

@Suite struct GestureClassifierTests {
    @Test func smallMovementIsATap() {
        #expect(FlipGestureClassifier.classify(translation: Vec2(0, 0), velocity: .zero) == .tap)
        #expect(FlipGestureClassifier.classify(translation: Vec2(5, -8), velocity: Vec2(900, 0)) == .tap)
    }

    @Test func swipingLeftIsNextAndRightIsPrevious() {
        #expect(FlipGestureClassifier.classify(translation: Vec2(-80, 4), velocity: Vec2(-600, 0)) == .swipe(.next, speed: 600))
        #expect(FlipGestureClassifier.classify(translation: Vec2(80, 4), velocity: Vec2(600, 0)) == .swipe(.previous, speed: 600))
    }

    @Test func swipeSpeedIsAlwaysPositive() {
        if case .swipe(_, let s) = FlipGestureClassifier.classify(translation: Vec2(-60, 0), velocity: Vec2(-1500, 0)) { #expect(s == 1500) } else { Issue.record("not a swipe") }
    }

    @Test func mostlyVerticalDragDoesNothing() {
        #expect(FlipGestureClassifier.classify(translation: Vec2(20, 90), velocity: Vec2(0, 800)) == FlipGesture.none)
        #expect(FlipGestureClassifier.classify(translation: Vec2(-30, -35), velocity: .zero) == FlipGesture.none)
    }

    @Test func tooShortASwipeDoesNothing() {
        // 12…24 points: moved too far for a tap, not far enough for a swipe.
        #expect(FlipGestureClassifier.classify(translation: Vec2(-18, 0), velocity: Vec2(-900, 0)) == FlipGesture.none)
        #expect(FlipGestureClassifier.classify(translation: Vec2(-24, 0), velocity: Vec2(-900, 0)) == .swipe(.next, speed: 900))
    }

    @Test func aSlowLongDragStillSwipes() {
        #expect(FlipGestureClassifier.classify(translation: Vec2(150, 10), velocity: .zero) == .swipe(.previous, speed: 0))
    }
}

@Suite struct VelocityTrackerTests {
    @Test func steadyDragGivesItsSpeed() {
        var t = FlipVelocityTracker()
        for i in 0...10 { t.add(x: 100 + Double(i) * 10, at: 5 + Double(i) * 0.01) }   // 1000 pt/s
        #expect(abs(t.velocity(endingAt: 5.1) - 1000) < 1e-6)
    }

    @Test func leftwardIsNegative() {
        var t = FlipVelocityTracker()
        for i in 0...6 { t.add(x: 200 - Double(i) * 8, at: Double(i) * 0.01) }
        #expect(t.velocity(endingAt: 0.06) < 0)
    }

    @Test func aFingerThatStoppedBeforeLiftingIsSlow() {
        var t = FlipVelocityTracker()
        for i in 0...10 { t.add(x: 100 + Double(i) * 10, at: Double(i) * 0.01) }
        #expect(t.velocity(endingAt: 0.1 + FlipVelocityTracker.window + 0.01) == 0)
    }

    @Test func onlyTheLastFewMomentsCount() {
        var t = FlipVelocityTracker()
        for i in 0...10 { t.add(x: Double(i) * 30, at: Double(i) * 0.01) }            // fast start
        for i in 1...20 { t.add(x: 300 + Double(i) * 0.5, at: 0.1 + Double(i) * 0.01) } // then slow
        #expect(abs(t.velocity(endingAt: 0.3)) < 100)
    }

    @Test func tooFewSamplesOrNoTimeGivesZero() {
        var t = FlipVelocityTracker()
        #expect(t.velocity(endingAt: 1) == 0)
        t.add(x: 5, at: 1)
        #expect(t.velocity(endingAt: 1) == 0)
        t.add(x: 50, at: 1.001)
        #expect(t.velocity(endingAt: 1.001) == 0)
    }

    @Test func ignoresNonFiniteSamplesAndResets() {
        var t = FlipVelocityTracker()
        t.add(x: .nan, at: 1); t.add(x: 1, at: .infinity)
        #expect(t == FlipVelocityTracker())
        t.add(x: 0, at: 0); t.add(x: 10, at: 0.05)
        #expect(t.velocity(endingAt: 0.05) == 200)
        t.reset()
        #expect(t.velocity(endingAt: 0.05) == 0)
    }
}

@Suite struct IndexTests {
    @Test func wrapsBothWays() {
        #expect(ChannelIndex.wrap(0, count: 6) == 0)
        #expect(ChannelIndex.wrap(6, count: 6) == 0)
        #expect(ChannelIndex.wrap(7, count: 6) == 1)
        #expect(ChannelIndex.wrap(-1, count: 6) == 5)
        #expect(ChannelIndex.wrap(-13, count: 6) == 5)
        #expect(ChannelIndex.wrap(5, count: 0) == 0)
        #expect(ChannelIndex.wrap(5, count: -2) == 0)
    }

    @Test func nextAndPreviousWrapAround() {
        #expect(ChannelIndex.next(5, count: 6) == 0)
        #expect(ChannelIndex.previous(0, count: 6) == 5)
        #expect(ChannelIndex.next(2, count: 6) == 3)
        #expect(ChannelIndex.previous(3, count: 6) == 2)
        #expect(ChannelIndex.next(0, count: 1) == 0)
    }

    @Test func goingAroundOnceComesBack() {
        var i = 2
        for _ in 0..<6 { i = ChannelIndex.next(i, count: 6) }
        #expect(i == 2)
        for _ in 0..<6 { i = ChannelIndex.previous(i, count: 6) }
        #expect(i == 2)
    }

    @Test func labelIsOneBasedWithTwoDigits() {
        #expect(ChannelIndex.label(0, count: 6) == "CH 01")
        #expect(ChannelIndex.label(2, count: 6) == "CH 03")
        #expect(ChannelIndex.label(8, count: 12) == "CH 09")
        #expect(ChannelIndex.label(9, count: 12) == "CH 10")
        #expect(ChannelIndex.label(11, count: 12) == "CH 12")
        #expect(ChannelIndex.label(6, count: 6) == "CH 01")
    }
}
