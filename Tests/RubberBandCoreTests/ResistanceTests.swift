import Testing
import Foundation
@testable import RubberBandCore

@Suite("Rubber band") struct ResistanceTests {
    /// The curve the hand is built on: offset * 0.55 / (1 + abs(offset) / 300).
    private func inspiration(_ offset: Double) -> Double {
        offset * 0.55 / (1 + abs(offset) / 300)
    }

    @Test func matchesTheInspirationCurve() {
        for x in stride(from: -800.0, through: 800.0, by: 25) {
            #expect(abs(RubberBandResistance.resist(x) - inspiration(x)) < 1e-12)
        }
        #expect(RubberBandResistance.resist(0) == 0)
        #expect(RubberBandResistance.resist(.nan) == 0)
        #expect(RubberBandResistance.resist(.infinity) == 0)
    }

    @Test func isOddAndNeverReachesTheAsymptote() {
        #expect(abs(RubberBandResistance.asymptote - 165) < 1e-12)
        for x in [1.0, 20, 100, 300, 1_000, 100_000] {
            let y = RubberBandResistance.resist(x)
            #expect(abs(RubberBandResistance.resist(-x) + y) < 1e-12)
            #expect(y > 0 && y < RubberBandResistance.asymptote)
            #expect(y < 0.55 * x)
        }
    }

    @Test func overpullGivesBackLessThanTheFingerMoved() {
        // Equal extra stretches of finger buy a smaller rise each time, and a long pull
        // stays under both the raw distance and the 165-point asymptote.
        let samples = [0.0, 120, 240, 360, 480].map { RubberBandResistance.resist($0) }
        let rises = zip(samples, samples.dropFirst()).map { $1 - $0 }
        #expect(rises[0] > rises[1] && rises[1] > rises[2] && rises[2] > rises[3])
        #expect(samples[4] < 480)
        #expect(samples[4] < RubberBandResistance.asymptote)
    }

    @Test func slopeFallsOffAndMatchesANumericalDerivative() {
        #expect(abs(RubberBandResistance.slope(at: 0) - 0.55) < 1e-12)
        #expect(RubberBandResistance.slope(at: 0) > RubberBandResistance.slope(at: 80))
        #expect(RubberBandResistance.slope(at: 80) > RubberBandResistance.slope(at: 400))
        #expect(RubberBandResistance.slope(at: .nan) == 0)
        let x = 140.0
        let h = 1e-4
        let numerical = (RubberBandResistance.resist(x + h) - RubberBandResistance.resist(x - h)) / (2 * h)
        #expect(abs(numerical - RubberBandResistance.slope(at: x)) < 1e-6)
        #expect(abs(RubberBandResistance.slope(at: -x) - RubberBandResistance.slope(at: x)) < 1e-12)
    }

    @Test func commitOnRiseOrOnAFastFlick() {
        let rise = RubberBandResistance.resist(200)
        #expect(rise > RubberBandLayout.commitRise)
        #expect(RubberBandResistance.decide(pullUp: 200, upwardVelocity: 0) == .commitDrag)
        #expect(RubberBandResistance.decide(pullUp: 40, upwardVelocity: 1_200) == .commitFlick)
        #expect(RubberBandResistance.decide(pullUp: 40, upwardVelocity: 100) == .springBack)
        // A flick that never really started does not commit.
        #expect(RubberBandResistance.decide(pullUp: 8, upwardVelocity: 2_000) == .springBack)
        #expect(RubberBandResistance.decide(pullUp: .nan, upwardVelocity: .nan) == .springBack)
    }

    @Test func dismissMirrorsTheDecision() {
        #expect(RubberBandResistance.decideDismiss(pullDown: 200, downwardVelocity: 0) == .commitDrag)
        #expect(RubberBandResistance.decideDismiss(pullDown: 30, downwardVelocity: 1_200) == .commitFlick)
        #expect(RubberBandResistance.decideDismiss(pullDown: 30, downwardVelocity: 10) == .springBack)
    }

    @Test func velocityIgnoresAFingerThatStopped() {
        var v = RubberBandVelocity()
        v.add(Vec2(0, 100), at: 0)
        v.add(Vec2(0, 40), at: 0.04)
        let fast = v.velocity(at: 0.04)
        #expect(abs(fast.y - (60 / 0.04)) < 1e-9)
        #expect(v.velocity(at: 0.2) == .zero)
        v.add(Vec2(.nan, 0), at: 0.05)
        #expect(v.velocity(at: 0.04).y > 0)
    }
}
