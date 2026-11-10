import Foundation
import Testing
@testable import RippleToHideCore

private let tap = Vec2(140, 80)
private let pass: Double = 72

@Suite("Hide and reveal") struct TripTests {
    @Test func startsShown() {
        let model = RippleModel()
        #expect(model.phase == .shown)
        #expect(!model.isHidden && !model.isAnimating && !model.showsMask)
        #expect(model.maskAmount == 0)
        #expect(model.shaderTime == 0 && model.shaderAmplitude == 0)
    }

    @Test func tapWhileShownHidesAndASecondTapReveals() {
        var model = RippleModel()
        #expect(model.toggle(at: tap, passRadius: pass) == [.beganHiding])
        #expect(model.phase == .hiding && !model.showsMask && model.shaderAmplitude == 14)
        #expect(model.shaderTime == 0)

        let hiding = drain(&model)
        #expect(hiding.contains(.haptic))
        #expect(hiding.contains(.swappedToMask))
        #expect(hiding.contains(.settledHidden))
        #expect(hiding.firstIndex(of: .haptic)! < hiding.firstIndex(of: .swappedToMask)!)
        #expect(model.phase == .hidden && model.isHidden && model.maskAmount == 1)
        #expect(model.shaderAmplitude == 0 && model.elapsed == 0)

        #expect(model.toggle(at: tap, passRadius: pass) == [.beganRevealing])
        #expect(model.phase == .revealing && model.showsMask)
        #expect(abs(model.shaderTime - model.rules.duration) < 1e-12)
        #expect(model.shaderAmplitude == 14)

        let revealing = drain(&model)
        #expect(revealing.contains(.swappedToDigits))
        #expect(revealing.contains(.haptic))
        #expect(revealing.contains(.settledShown))
        #expect(revealing.firstIndex(of: .swappedToDigits)! < revealing.firstIndex(of: .haptic)!)
        #expect(model.phase == .shown && !model.isHidden && model.maskAmount == 0)
    }

    @Test func hapticAndSwapFireOnceAtTheThresholds() {
        var model = RippleModel()
        _ = model.toggle(at: tap, passRadius: pass)
        let hapticAt = pass / model.rules.speed
        let half = model.rules.duration * model.rules.swapFraction
        #expect(model.advance(by: hapticAt - 0.01).isEmpty)
        #expect(!model.showsMask && model.maskAmount == 0)
        #expect(model.advance(by: 0.02) == [.haptic])
        #expect(model.advance(by: half - model.elapsed - 0.01).isEmpty)
        #expect(model.advance(by: 0.02) == [.swappedToMask])
        #expect(model.showsMask && model.maskAmount == 1)
        #expect(model.isHidden)
        // A second crossing is not possible; more time does not repeat the swap.
        #expect(model.advance(by: 0.02).isEmpty)
    }

    @Test func revealShaderTimeRunsBackward() {
        var model = settledHidden()
        _ = model.toggle(at: tap, passRadius: pass)
        let start = model.shaderTime
        _ = model.advance(by: 0.1)
        #expect(model.shaderTime < start)
        #expect(abs(model.shaderTime - (model.rules.duration - 0.1)) < 1e-12)
        let sample = RippleWave(rules: model.rules).samplePosition(
            position: Vec2(200, 80), tap: model.tap, time: model.shaderTime, amplitude: model.shaderAmplitude)
        #expect(sample.x.isFinite && sample.y.isFinite)
    }

    @Test func oneLargeStepEmitsHapticThenSwapThenSettle() {
        var model = RippleModel()
        _ = model.toggle(at: tap, passRadius: pass)
        #expect(model.advance(by: 2) == [.haptic, .swappedToMask, .settledHidden])
        #expect(model.phase == .hidden && model.elapsed == 0)

        _ = model.toggle(at: tap, passRadius: pass)
        #expect(model.advance(by: 2) == [.swappedToDigits, .haptic, .settledShown])
        #expect(model.phase == .shown)
    }

    @Test func tapsDuringATripAreIgnored() {
        var model = RippleModel()
        _ = model.toggle(at: tap, passRadius: pass)
        #expect(model.toggle(at: Vec2(1, 1), passRadius: 10).isEmpty)
        #expect(model.setHidden(false, at: tap, passRadius: pass).isEmpty)
        #expect(model.phase == .hiding && model.tap == tap)
        _ = model.advance(by: 2)
        #expect(model.setHidden(true, at: tap, passRadius: pass).isEmpty)
        #expect(model.phase == .hidden)
    }

    @Test func setHiddenFromTheOppositeSettledStateStartsTheTrip() {
        var model = RippleModel()
        #expect(model.setHidden(false, at: tap, passRadius: pass).isEmpty)
        #expect(model.setHidden(true, at: tap, passRadius: pass) == [.beganHiding])
        _ = model.advance(by: 2)
        #expect(model.setHidden(true, at: tap, passRadius: pass).isEmpty)
        #expect(model.setHidden(false, at: tap, passRadius: pass) == [.beganRevealing])
    }

    @Test func aFrontThatNeverArrivesDoesNotTick() {
        var model = RippleModel()
        let tooFar = model.rules.reach + 50
        _ = model.toggle(at: tap, passRadius: tooFar)
        let events = drain(&model)
        #expect(!events.contains(.haptic))
        #expect(events.contains(.swappedToMask) && events.contains(.settledHidden))
    }

    @Test func zeroOrNegativePassRadiusNeverTicks() {
        for radius in [0.0, -8] {
            var model = RippleModel()
            _ = model.toggle(at: tap, passRadius: radius)
            #expect(!drain(&model).contains(.haptic))
        }
    }

    @Test func nonFiniteTapAndRadiusAreDropped() {
        var model = RippleModel()
        _ = model.toggle(at: Vec2(.nan, 4), passRadius: .infinity)
        #expect(model.tap == .zero)
        #expect(model.passRadius == 0)
    }

    @Test func advanceDoesNothingWhenSettledOrGivenABadStep() {
        var model = RippleModel()
        #expect(model.advance(by: 0.1).isEmpty)
        _ = model.toggle(at: tap, passRadius: pass)
        #expect(model.advance(by: 0).isEmpty)
        #expect(model.advance(by: -0.2).isEmpty)
        #expect(model.advance(by: .nan).isEmpty)
        #expect(model.phase == .hiding && model.elapsed == 0)
    }

    @Test func snapSetsTheSettledMaskWithoutATrip() {
        var model = RippleModel()
        model.snap(hidden: true)
        #expect(model.phase == .hidden && model.isHidden && model.maskAmount == 1)
        #expect(!model.isAnimating)
        model.snap(hidden: false)
        #expect(model.phase == .shown && model.maskAmount == 0)
    }
}

@Suite("Reduce Motion") struct ReduceMotionTests {
    @Test func crossfadesWithoutARippleOrAHaptic() {
        var model = RippleModel(reduceMotion: true)
        #expect(model.toggle(at: tap, passRadius: pass) == [.beganHiding])
        #expect(model.shaderTime == 0 && model.shaderAmplitude == 0)
        let quarter = model.activeDuration / 4
        #expect(model.advance(by: quarter).isEmpty)
        #expect(abs(model.maskAmount - 0.25) < 1e-12)
        #expect(!model.showsMask)
        #expect(model.advance(by: quarter) == [.swappedToMask])
        #expect(abs(model.maskAmount - 0.5) < 1e-12)
        #expect(model.isHidden)
        let rest = drain(&model)
        #expect(!rest.contains(.haptic))
        #expect(rest.contains(.settledHidden))
        #expect(model.phase == .hidden && model.maskAmount == 1)
        #expect(abs(model.activeDuration - 0.28) < 1e-12)
    }

    @Test func revealCrossfadesBackToTheDigits() {
        var model = RippleModel(reduceMotion: true)
        model.snap(hidden: true)
        _ = model.toggle(at: tap, passRadius: pass)
        #expect(model.maskAmount == 1)
        _ = model.advance(by: model.activeDuration / 2)
        #expect(model.showsMask == false)
        #expect(abs(model.maskAmount - 0.5) < 1e-12)
        let events = model.advance(by: model.activeDuration)
        #expect(events.contains(.settledShown))
        #expect(!events.contains(.haptic))
        #expect(model.phase == .shown && model.maskAmount == 0)
    }
}

private func drain(_ model: inout RippleModel) -> [RippleEvent] {
    var events: [RippleEvent] = []
    for _ in 0..<40 {
        let step = model.advance(by: 0.05)
        events.append(contentsOf: step)
        if !model.isAnimating { break }
    }
    return events
}

private func settledHidden() -> RippleModel {
    var model = RippleModel()
    _ = model.toggle(at: tap, passRadius: pass)
    _ = model.advance(by: 2)
    return model
}
