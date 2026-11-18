import Foundation
import Testing
@testable import GlassMorphCore

extension GlassMorphModel {
    /// Steps `seconds` at 60 fps and returns every event, in order.
    @discardableResult
    mutating func run(_ seconds: Double, fps: Double = 60) -> [GlassMorphEvent] {
        var out: [GlassMorphEvent] = []
        let n = Int((seconds * fps).rounded())
        for _ in 0..<n { out += step(1 / fps) }
        return out
    }

    /// Pays, then runs until the card is back. The returned list includes `.paid`.
    @discardableResult
    mutating func play() -> [GlassMorphEvent] {
        var out = pay()
        var guardCount = 0
        while !out.contains(.returned) && guardCount < 600 {
            out += step(1.0 / 60)
            guardCount += 1
        }
        return out
    }
}

private let cycle: [GlassMorphEvent] = [.paid, .settled, .unfolding, .returned]

@Suite("Layout") struct GlassMorphLayoutTests {
    @Test func theCardAndThePillAreTheTuningFrames() {
        let card = GlassMorphLayout.frame(progress: 0)
        #expect(card.center == GlassMorphTuning.stageCenter)
        #expect(card.width == GlassMorphTuning.cardWidth)
        #expect(card.height == GlassMorphTuning.cardHeight)
        #expect(card.cornerRadius == GlassMorphTuning.cardCorner)
        #expect(card.tilt == GlassMorphTuning.cardTilt)
        #expect(abs(card.tilt * 180 / .pi + 3) < 1e-12)

        let pill = GlassMorphLayout.frame(progress: 1)
        #expect(pill.center == GlassMorphTuning.stageCenter)
        #expect(pill.width == GlassMorphTuning.pillWidth)
        #expect(pill.height == GlassMorphTuning.pillHeight)
        #expect(pill.cornerRadius == GlassMorphTuning.pillCorner)
        #expect(pill.tilt == 0)
    }

    @Test func halfwayIsTheAverageAndOvershootKeepsGoing() {
        let mid = GlassMorphLayout.frame(progress: 0.5)
        #expect(abs(mid.width - (GlassMorphTuning.cardWidth + GlassMorphTuning.pillWidth) / 2) < 1e-12)
        #expect(abs(mid.height - (GlassMorphTuning.cardHeight + GlassMorphTuning.pillHeight) / 2) < 1e-12)
        #expect(abs(mid.tilt - GlassMorphTuning.cardTilt / 2) < 1e-12)

        let over = GlassMorphLayout.frame(progress: 1.1)
        let expectedWidth = GlassMorphTuning.pillWidth + 0.1 * (GlassMorphTuning.pillWidth - GlassMorphTuning.cardWidth)
        #expect(abs(over.width - expectedWidth) < 1e-9)
        #expect(over.width < GlassMorphTuning.pillWidth)
        #expect(over.tilt == 0)
        let parked = GlassMorphLayout.light(.amber, progress: 1.1)
        #expect(parked.center == GlassMorphTuning.amberLogo)
        #expect(parked.radius == GlassMorphTuning.amberLogoRadius)
    }

    @Test func aNonFiniteProgressReadsAsTheCard() {
        let frame = GlassMorphLayout.frame(progress: .nan)
        #expect(frame.width == GlassMorphTuning.cardWidth)
        #expect(frame.tilt == GlassMorphTuning.cardTilt)
        let light = GlassMorphLayout.light(.amber, progress: .infinity)
        #expect(light.center == GlassMorphTuning.amberRest)
    }

    @Test func lightsTravelFromTheBackdropToTheLogo() {
        let amber0 = GlassMorphLayout.light(.amber, progress: 0)
        let red0 = GlassMorphLayout.light(.red, progress: 0)
        #expect(amber0.center == GlassMorphTuning.amberRest)
        #expect(amber0.radius == GlassMorphTuning.amberRestRadius)
        #expect(amber0.blur == GlassMorphTuning.amberRestBlur)
        #expect(red0.center == GlassMorphTuning.redRest)
        #expect(red0.radius == GlassMorphTuning.redRestRadius)

        let amber1 = GlassMorphLayout.light(.amber, progress: 1)
        let red1 = GlassMorphLayout.light(.red, progress: 1)
        #expect(amber1.center == GlassMorphTuning.amberLogo)
        #expect(amber1.radius == GlassMorphTuning.amberLogoRadius)
        #expect(amber1.blur == 0)
        #expect(red1.center == GlassMorphTuning.redLogo)
        #expect(red1.radius == GlassMorphTuning.redLogoRadius)
        #expect(red1.blur == 0)

        let gap = GlassMorphTuning.amberLogo.distance(to: GlassMorphTuning.redLogo)
        #expect(abs(gap - 22) < 1e-12)
        #expect(amber0.center.distance(to: red0.center) > gap * 10)

        let mid = GlassMorphLayout.light(.red, progress: 0.5)
        let expected = Vec2.lerp(GlassMorphTuning.redRest, GlassMorphTuning.redLogo, 0.5)
        #expect(abs(mid.center.x - expected.x) < 1e-12)
        #expect(abs(mid.center.y - expected.y) < 1e-12)
    }

    @Test func theHalfTurnRunsFromZeroToPi() {
        #expect(GlassMorphLayout.flipAngle(at: 0) == 0)
        #expect(GlassMorphLayout.flipAngle(at: -2) == 0)
        #expect(GlassMorphLayout.flipAngle(at: .nan) == 0)
        let duration = GlassMorphTuning.unfoldDuration
        #expect(abs(GlassMorphLayout.flipAngle(at: duration / 2) - .pi / 2) < 1e-12)
        #expect(abs(GlassMorphLayout.flipAngle(at: duration) - .pi) < 1e-12)
        #expect(abs(GlassMorphLayout.flipAngle(at: duration * 2) - .pi) < 1e-12)

        var previous = -1.0
        for i in 0...20 {
            let angle = GlassMorphLayout.flipAngle(at: duration * Double(i) / 20)
            #expect(angle >= previous)
            previous = angle
        }
    }

    @Test func displayFlipComesBackUpright() {
        #expect(GlassMorphLayout.displayFlip(0, reduceMotion: false) == 0)
        #expect(abs(GlassMorphLayout.displayFlip(.pi / 2, reduceMotion: false) - .pi / 2) < 1e-12)
        #expect(abs(GlassMorphLayout.displayFlip(.pi, reduceMotion: false)) < 1e-12)
        #expect(abs(GlassMorphLayout.displayFlip(.pi * 0.75, reduceMotion: false) + .pi / 4) < 1e-12)
        #expect(GlassMorphLayout.displayFlip(.pi / 2, reduceMotion: true) == 0)
    }

    @Test func facesFadeOnTheWayInAndSwapOnTheTurn() {
        #expect(GlassMorphLayout.cardContentOpacity(phase: .card, progress: 0, flip: 0, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.dotOpacity(phase: .card, progress: 0, flip: 0, reduceMotion: false) == 0)
        #expect(GlassMorphLayout.glowOpacity(phase: .card, progress: 0, flip: 0, reduceMotion: false) == 1)

        #expect(GlassMorphLayout.cardContentOpacity(phase: .morphing, progress: 0, flip: 0, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.cardContentOpacity(phase: .morphing, progress: 1, flip: 0, reduceMotion: false) == 0)
        #expect(GlassMorphLayout.dotOpacity(phase: .morphing, progress: 1, flip: 0, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.glowOpacity(phase: .pill, progress: 1, flip: 0, reduceMotion: false) == 0)

        #expect(GlassMorphLayout.cardContentOpacity(phase: .unfolding, progress: 0.8, flip: 0.2, reduceMotion: false) == 0)
        #expect(GlassMorphLayout.dotOpacity(phase: .unfolding, progress: 0.8, flip: 0.2, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.cardContentOpacity(phase: .unfolding, progress: 0.2, flip: .pi, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.dotOpacity(phase: .unfolding, progress: 0.2, flip: .pi, reduceMotion: false) == 0)
        #expect(GlassMorphLayout.glowOpacity(phase: .unfolding, progress: 0, flip: .pi, reduceMotion: false) == 1)
    }

    @Test func reduceMotionIsACrossfadeWithNoEdge() {
        let card = GlassMorphLayout.cardContentOpacity(phase: .morphing, progress: 0.25, flip: 1, reduceMotion: true)
        let dots = GlassMorphLayout.dotOpacity(phase: .morphing, progress: 0.25, flip: 1, reduceMotion: true)
        let glow = GlassMorphLayout.glowOpacity(phase: .unfolding, progress: 0.25, flip: 1, reduceMotion: true)
        #expect(abs(card - 0.75) < 1e-12)
        #expect(abs(dots - 0.25) < 1e-12)
        #expect(abs(glow - 0.75) < 1e-12)
        #expect(GlassMorphLayout.edgeGlow(phase: .unfolding, flip: .pi / 2, reduceMotion: true) == 0)
        #expect(GlassMorphLayout.edgeGlow(phase: .unfolding, flip: .pi / 2, reduceMotion: false) == 1)
        #expect(GlassMorphLayout.edgeGlow(phase: .unfolding, flip: 0, reduceMotion: false) == 0)
        #expect(GlassMorphLayout.edgeGlow(phase: .pill, flip: .pi / 2, reduceMotion: false) == 0)
    }

    @Test func thePayButtonRoundTripsAndOnlyTheButtonHits() {
        let local = Vec2(24, -36)
        let world = GlassMorphLayout.worldPoint(local, center: GlassMorphTuning.stageCenter, tilt: GlassMorphTuning.cardTilt)
        let back = GlassMorphLayout.localPoint(world, center: GlassMorphTuning.stageCenter, tilt: GlassMorphTuning.cardTilt)
        #expect(abs(back.x - local.x) < 1e-9)
        #expect(abs(back.y - local.y) < 1e-9)

        let model = GlassMorphModel()
        let button = GlassMorphLayout.worldPoint(GlassMorphTuning.payButtonLocal,
                                                  center: GlassMorphTuning.stageCenter,
                                                  tilt: GlassMorphTuning.cardTilt)
        #expect(model.containsPay(button))
        let amount = GlassMorphLayout.worldPoint(Vec2(0, GlassMorphTuning.amountLocalY),
                                                  center: GlassMorphTuning.stageCenter,
                                                  tilt: GlassMorphTuning.cardTilt)
        #expect(!model.containsPay(amount))
        #expect(!model.containsPay(.zero))
        #expect(!model.containsPay(Vec2(.nan, 1)))
        #expect(!GlassMorphTuning.payButton.contains(Vec2(.infinity, 0)))
    }
}

@Suite("State machine") struct GlassMorphModelTests {
    @Test func restIgnoresTimeAndMisses() {
        var model = GlassMorphModel()
        #expect(model.isAtRest)
        #expect(model.accessibilityValue == GlassMorphTuning.readyValue)
        #expect(model.step(1) == [])
        #expect(model.step(0) == [] && model.step(-0.2) == [] && model.step(.nan) == [])
        #expect(model.clock == 0)
        #expect(model.pay(at: .zero) == [])
        #expect(model.pay(at: Vec2(.nan, 0)) == [])
        #expect(model.phase == .card)
        #expect(model.settledCount == 0)
    }

    @Test func aSecondPayWhileBusyDoesNothing() {
        var model = GlassMorphModel()
        #expect(model.pay() == [.paid])
        #expect(model.phase == .morphing)
        #expect(model.accessibilityValue == GlassMorphTuning.payingValue)
        #expect(model.pay() == [])
        #expect(model.settledCount == 0)
        let button = GlassMorphLayout.worldPoint(GlassMorphTuning.payButtonLocal,
                                                  center: GlassMorphTuning.stageCenter,
                                                  tilt: GlassMorphTuning.cardTilt)
        #expect(!model.containsPay(button))
        #expect(model.pay(at: button) == [])
    }

    @Test func badFramesDoNotMoveTheMorph() {
        var model = GlassMorphModel()
        #expect(model.pay() == [.paid])
        #expect(model.step(0) == [])
        #expect(model.step(-1) == [])
        #expect(model.step(.nan) == [])
        #expect(model.step(.infinity) == [])
        #expect(model.progress == 0)
        #expect(model.clock == 0)
    }

    @Test func aStalledFrameAdvancesAtMostATenth() {
        var model = GlassMorphModel()
        _ = model.pay()
        _ = model.step(10)
        #expect(model.clock <= GlassMorphTuning.maxFrame + 1e-12)
        #expect(model.progress.isFinite && model.progressVelocity.isFinite)
        #expect(model.amber.center.x.isFinite && model.red.center.y.isFinite)
    }

    @Test func fullMotionOvershootsThenSettlesTheLightsOnce() throws {
        var model = GlassMorphModel()
        var peak = 0.0
        var events = model.pay()
        var steps = 0
        while model.phase == .morphing && steps < 400 {
            peak = max(peak, model.progress)
            events += model.step(1.0 / 60)
            steps += 1
        }
        #expect(peak > 1.02)
        #expect(events == [.paid, .settled])
        #expect(model.phase == .pill)
        #expect(model.settledCount == 1)
        #expect(model.progress == 1)
        #expect(model.progressVelocity == 0)
        #expect(model.flipAngle == 0)
        #expect(model.amber.center.distance(to: GlassMorphTuning.amberLogo) < 1e-9)
        #expect(model.red.center.distance(to: GlassMorphTuning.redLogo) < 1e-9)
        #expect(model.amber.radius == GlassMorphTuning.amberLogoRadius)
        #expect(model.red.radius == GlassMorphTuning.redLogoRadius)
        #expect(model.accessibilityValue == GlassMorphTuning.paidValue)
        let settledAt = try #require(model.settledClock)
        #expect(settledAt > 0.4 && settledAt < 1.2)
    }

    @Test func thePillHoldsForASecondThenTurnsOver() throws {
        var model = GlassMorphModel()
        let events = model.play()
        #expect(events == cycle)
        #expect(model.settledCount == 1)
        let settledAt = try #require(model.settledClock)
        let openedAt = try #require(model.unfoldClock)
        #expect(abs((openedAt - settledAt) - GlassMorphTuning.holdDuration) < GlassMorphTuning.substep + 1e-9)
        #expect(model.phase == .card)
        #expect(model.isAtRest)
        #expect(model.frame.width == GlassMorphTuning.cardWidth)
        #expect(model.flipAngle == 0)
        #expect(model.displayFlip == 0)
        #expect(model.accessibilityValue == GlassMorphTuning.readyValue)
    }

    @Test func theFlipClimbsToAHalfTurnAndOnlyThenReturns() {
        var model = GlassMorphModel()
        _ = model.pay()
        var flips: [Double] = []
        var previous = 0.0
        var sawReturn = false
        for _ in 0..<600 {
            previous = model.flipAngle
            let events = model.step(1.0 / 60)
            if model.phase == .unfolding { flips.append(model.flipAngle) }
            if events.contains(.returned) {
                sawReturn = true
                #expect(previous > 3)
                #expect(model.flipAngle == 0)
                break
            }
        }
        #expect(sawReturn)
        #expect(flips.count > 5)
        for pair in zip(flips, flips.dropFirst()) {
            #expect(pair.1 >= pair.0 - 1e-9)
        }
        #expect(model.edgeGlow == 0)
    }

    @Test func aSecondPaymentSettlesAgain() {
        var model = GlassMorphModel()
        #expect(model.play() == cycle)
        #expect(model.play() == cycle)
        #expect(model.settledCount == 2)
        #expect(model.isAtRest)
    }

    @Test func theSameStepsReplay() {
        func snapshot() -> (GlassMorphPhase, Double, Double, Vec2) {
            var model = GlassMorphModel()
            _ = model.pay()
            model.run(0.4)
            return (model.phase, model.progress, model.flipAngle, model.amber.center)
        }
        let a = snapshot()
        let b = snapshot()
        #expect(a.0 == b.0)
        #expect(a.1 == b.1)
        #expect(a.2 == b.2)
        #expect(a.3 == b.3)
    }

    @Test func reduceMotionCrossfadesAndNeverFlipsOrOvershoots() {
        var model = GlassMorphModel(reduceMotion: true)
        var peak = 0.0
        var maxFlip = 0.0
        var morphSamples: [Double] = []
        let events = model.pay() + {
            var out: [GlassMorphEvent] = []
            var steps = 0
            while !out.contains(.returned) && steps < 600 {
                if model.phase == .morphing { morphSamples.append(model.progress) }
                peak = max(peak, model.progress)
                maxFlip = max(maxFlip, abs(model.flipAngle))
                out += model.step(1.0 / 60)
                steps += 1
            }
            return out
        }()
        #expect(events == cycle)
        #expect(peak <= 1 + 1e-9)
        #expect(maxFlip == 0)
        #expect(model.displayFlip == 0)
        #expect(model.settledCount == 1)
        #expect(model.amber.center == GlassMorphTuning.amberLogo || model.phase == .card)
        for pair in zip(morphSamples, morphSamples.dropFirst()) {
            #expect(pair.1 >= pair.0 - 1e-12)
        }
        #expect(model.isAtRest)
    }

    @Test func reduceMotionStillWaitsASecondOnThePill() throws {
        var model = GlassMorphModel(reduceMotion: true)
        _ = model.play()
        let settledAt = try #require(model.settledClock)
        let openedAt = try #require(model.unfoldClock)
        #expect(abs((openedAt - settledAt) - GlassMorphTuning.holdDuration) < GlassMorphTuning.substep + 1e-9)
        #expect(settledAt < GlassMorphTuning.fadeDuration + GlassMorphTuning.substep)
    }

    @Test func switchingOnReduceMotionDropsTheFlip() {
        var model = GlassMorphModel()
        _ = model.pay()
        var steps = 0
        while model.phase != .unfolding && steps < 600 {
            _ = model.step(1.0 / 60)
            steps += 1
        }
        #expect(model.phase == .unfolding)
        model.run(0.2)
        #expect(model.flipAngle > 0.5)
        model.setReduceMotion(true)
        #expect(model.flipAngle == 0)
        #expect(model.progressVelocity == 0)
        #expect(model.displayFlip == 0)
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        let before = model.progress
        model.run(0.05)
        #expect(model.progress < before)
        #expect(model.flipAngle == 0)
    }

    @Test func switchingOffReduceMotionKeepsTheOpenAmount() {
        var model = GlassMorphModel(reduceMotion: true)
        _ = model.pay()
        var steps = 0
        while model.phase != .unfolding && steps < 600 {
            _ = model.step(1.0 / 60)
            steps += 1
        }
        model.run(GlassMorphTuning.fadeDuration * 0.25)
        let progress = model.progress
        model.setReduceMotion(false)
        #expect(abs(model.flipAngle - GlassMorphLayout.flipAngle(at: (1 - progress) * GlassMorphTuning.unfoldDuration)) < 1e-9)
        #expect(model.phase == .unfolding)
    }

    @Test func resetReturnsToTheCardAndKeepsTheMotionSetting() {
        var model = GlassMorphModel(reduceMotion: true)
        _ = model.pay()
        model.run(0.1)
        #expect(model.phase == .morphing)
        model.reset()
        #expect(model.isAtRest)
        #expect(model.reduceMotion)
        #expect(model.settledCount == 0)
        #expect(model.settledClock == nil)
    }

    @Test func theCopyAndTheColoursStayPut() {
        #expect(GlassMorphTuning.announcement == "Payment complete")
        #expect(GlassMorphTuning.defaultAmount == "$48.00")
        #expect(GlassMorphTuning.defaultLabel == "Solune")
        #expect(GlassMorphTuning.payTitle == "Pay")
        #expect(GlassMorphTuning.caption == "Glass wallet")
        #expect(abs(GlassMorphTuning.amber.red - 1) < 1e-12)
        #expect(abs(GlassMorphTuning.amber.green - 176.0 / 255.0) < 1e-12)
        #expect(abs(GlassMorphTuning.amber.blue - 64.0 / 255.0) < 1e-12)
        #expect(abs(GlassMorphTuning.red.green - 59.0 / 255.0) < 1e-12)
        #expect(abs(GlassMorphTuning.red.blue - 78.0 / 255.0) < 1e-12)
        #expect(GlassMorphTuning.canvasWidth == 390)
        #expect(GlassMorphTuning.canvasHeight == 844)
    }
}
