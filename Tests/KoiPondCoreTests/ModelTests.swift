import Foundation
import Testing
@testable import KoiPondCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }

private func pump(_ model: inout KoiPondModel, seconds: Double) -> [KoiPondEvent] {
    var events: [KoiPondEvent] = []
    var left = seconds
    let step = KoiPondTuning.fixedStep
    while left > 1e-9 {
        let h = min(left, step)
        events.append(contentsOf: model.step(h))
        left -= h
    }
    return events
}

private func segmentLengths(_ spine: [Vec2]) -> [Double] {
    (1..<spine.count).map { spine[$0].distance(to: spine[$0 - 1]) }
}

private func expectSpine(_ model: KoiPondModel, source: SourceLocation = #_sourceLocation) {
    for fish in model.fish {
        for length in segmentLengths(fish.spine) {
            #expect(near(length, KoiPondTuning.segmentLength, 1e-6), sourceLocation: source)
        }
        let posed = fish.posedSpine(at: model.swimTime)
        #expect(posed.count == KoiPondTuning.spineCount, sourceLocation: source)
        #expect(near(posed[0].x, fish.spine[0].x, 1e-9) && near(posed[0].y, fish.spine[0].y, 1e-9), sourceLocation: source)
        for length in segmentLengths(posed) {
            #expect(near(length, KoiPondTuning.segmentLength, 1e-6), sourceLocation: source)
        }
    }
}

@Suite("Koi pond math") struct KoiPondMathTests {
    @Test func sineMatchesTheKnownQuadrants() {
        #expect(near(KoiPondMath.sin(0), 0, 1e-12))
        #expect(near(KoiPondMath.sin(KoiPondMath.halfPi), 1, 1e-9))
        #expect(near(KoiPondMath.cos(0), 1, 1e-9))
        #expect(near(KoiPondMath.cos(KoiPondMath.pi), -1, 1e-9))
        #expect(near(KoiPondMath.sin(-KoiPondMath.halfPi), -1, 1e-9))
    }

    @Test func atanAgreesWithTheQuarterTurns() {
        #expect(near(KoiPondMath.atan(0), 0, 1e-12))
        #expect(near(KoiPondMath.atan(1), KoiPondMath.pi / 4, 1e-8))
        #expect(near(KoiPondMath.atan(-1), -KoiPondMath.pi / 4, 1e-8))
        #expect(near(KoiPondMath.atan2(0, 1), 0, 1e-8))
        #expect(near(KoiPondMath.atan2(1, 0), KoiPondMath.halfPi, 1e-8))
        #expect(near(KoiPondMath.atan2(0, -1), KoiPondMath.pi, 1e-8))
        #expect(near(KoiPondMath.atan2(-1, 0), -KoiPondMath.halfPi, 1e-8))
        #expect(KoiPondMath.atan2(.nan, 1) == 0)
    }

    @Test func wrapStaysOnTheOpenInterval() {
        #expect(near(KoiPondMath.wrap(0), 0))
        #expect(near(KoiPondMath.wrap(KoiPondMath.pi), -KoiPondMath.pi))
        #expect(near(KoiPondMath.wrap(-KoiPondMath.pi), -KoiPondMath.pi))
        #expect(near(KoiPondMath.wrap(3 * KoiPondMath.pi), -KoiPondMath.pi))
        let turned = KoiPondMath.turn(0, toward: 1, rate: 1, dt: 0.2)
        #expect(near(turned, 0.2))
        let other = KoiPondMath.turn(0, toward: -1, rate: 1, dt: 0.2)
        #expect(near(other, -0.2))
    }
}

@Suite("Koi pond") struct KoiPondModelTests {
    @Test func defaultsClampsAndVoiceOver() {
        let model = KoiPondModel()
        #expect(model.koiCount == 6)
        #expect(model.phase == .laps)
        #expect(model.accessibilityLabel == "Pond, 6 koi")
        #expect(model.accessibilityValue == KoiPondTuning.swimmingValue)
        #expect(KoiPondTuning.feedAction == "Feed koi")
        #expect(KoiPondTuning.nibblingValue == "Koi nibbling")
        #expect(KoiPondModel(koiCount: 0).koiCount == 1)
        #expect(KoiPondModel(koiCount: 40).koiCount == KoiPondTuning.maxKoi)
        #expect(model.fish.allSatisfy { $0.mode == .lap && $0.spine.count == 5 })
        #expect(KoiPondTuning.palettes.count == 6)
        expectSpine(model)
    }

    @Test func theSameSeedIsTheSamePond() {
        var a = KoiPondModel(seed: 42)
        var b = KoiPondModel(seed: 42)
        a.beginTouch(at: Vec2(160, 420))
        b.beginTouch(at: Vec2(160, 420))
        let left = pump(&a, seconds: 2.4)
        let right = pump(&b, seconds: 2.4)
        #expect(a == b)
        #expect(left == right)
        let other = KoiPondModel(seed: 99)
        #expect(other.fish[0].head != a.fish[0].head || other.fish[1].lapAngle != a.fish[1].lapAngle)
    }

    @Test func nonFiniteInputIsIgnored() {
        var model = KoiPondModel(seed: 3)
        let before = model
        #expect(model.step(.nan).isEmpty)
        #expect(model.step(0).isEmpty)
        #expect(model.step(-0.2).isEmpty)
        #expect(model.beginTouch(at: Vec2(.infinity, 10)).isEmpty)
        #expect(model == before)
        model.beginTouch(at: Vec2(-40, -80))
        #expect(model.phase == .arming)
        #expect(KoiPondTuning.containsFinger(model.finger))
    }

    @Test func lapsKeepTheChainAndTheTailIsASine() {
        var model = KoiPondModel(seed: 7)
        _ = pump(&model, seconds: 1.2)
        #expect(model.phase == .laps)
        #expect(model.fish.allSatisfy { $0.mode == .lap })
        expectSpine(model)
        for fish in model.fish {
            let tip = fish.posedSpine(at: model.swimTime)[4]
            #expect(tip.distance(to: fish.spine[4]) > 0.2)
            #expect(KoiPondTuning.containsOuter(fish.head, slop: 1))
        }

        let fish = model.fish[0]
        let crest = (KoiPondMath.halfPi - fish.tailPhase + 4 * KoiPondTuning.tailLag) / KoiPondTuning.tailOmega
        let flat = (0 - fish.tailPhase + 4 * KoiPondTuning.tailLag) / KoiPondTuning.tailOmega
        #expect(near(wave(fish, at: crest), KoiPondTuning.tailAmplitude, 1e-6))
        #expect(near(wave(fish, at: flat), 0, 1e-6))
        #expect(near(wave(fish, at: crest + KoiPondMath.pi / KoiPondTuning.tailOmega), -KoiPondTuning.tailAmplitude, 1e-6))
    }

    @Test func aShortPressDoesNotCallThem() {
        var model = KoiPondModel(seed: 4)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        let events = pump(&model, seconds: KoiPondTuning.longPress * 0.4)
        #expect(events.isEmpty)
        #expect(model.phase == .arming)
        #expect(model.ripples.contains { $0.kind == .gather })
        let ended = model.endTouch()
        #expect(ended.isEmpty)
        #expect(model.phase == .laps)
        #expect(model.arrivalOrder.isEmpty)
        #expect(model.fish.allSatisfy { $0.mode == .lap })
        #expect(model.accessibilityValue == "Koi swimming")
    }

    @Test func theLongPressOpensARippleAndStaggersTheSchool() {
        var model = KoiPondModel(seed: 5)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: KoiPondTuning.longPress + KoiPondTuning.fixedStep)
        #expect(model.phase == .gathering)
        #expect(model.holding)
        #expect(model.accessibilityValue == "Koi nibbling")
        let gather = model.ripples.first { $0.kind == .gather }
        #expect(gather != nil)
        #expect((gather?.radius ?? 0) > 1)

        _ = pump(&model, seconds: KoiPondTuning.stagger * 0.45)
        #expect(model.fish[0].mode != .lap)
        #expect(model.fish[1].mode == .lap)
        #expect(model.fish[2].mode == .lap)
        _ = pump(&model, seconds: KoiPondTuning.stagger)
        #expect(model.fish[1].mode != .lap)
        #expect(model.fish[2].mode == .lap)
        expectSpine(model)
    }

    @Test func everyKoiReachesTheFingerInOrderAndInsideThePond() {
        var model = KoiPondModel(seed: KoiPondTuning.defaultSeed)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: 8)
        #expect(model.arrivalOrder == Array(0..<model.koiCount))
        #expect(model.fish.allSatisfy { $0.mode == .nibbling })
        #expect(KoiPondTuning.containsOuter(model.finger))
        for fish in model.fish {
            #expect(fish.head.distance(to: model.finger) <= KoiPondTuning.nibbleGap + 0.5)
            #expect(KoiPondTuning.containsOuter(fish.head, slop: 1))
            for point in fish.posedSpine(at: model.swimTime) {
                #expect(KoiPondTuning.containsOuter(point, slop: 4))
            }
        }
        expectSpine(model)
    }

    @Test func nibblesFireOncePerBobAndLeaveARipple() {
        var model = KoiPondModel(seed: 11)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        let events = pump(&model, seconds: 9)
        let nibbles = events.compactMap { event -> Int? in
            if case .nibble(let index) = event { return index }
            return nil
        }
        #expect(Set(nibbles) == Set(0..<model.koiCount))
        #expect(model.nibbleCount == nibbles.count)
        #expect(model.ripples.contains { $0.kind == .nibble })
        let window = nibbles.filter { _ in true }
        #expect(window.count < model.koiCount * 20)
        expectSpine(model)
    }

    @Test func lettingGoScattersThenReturnsToTheLaps() {
        var model = KoiPondModel(seed: 8)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: 4.5)
        #expect(model.fish.contains { $0.mode == .nibbling })
        let before = model.fish[0].head
        let released = model.endTouch()
        #expect(released == [.released])
        #expect(model.phase == .scattering)
        #expect(model.accessibilityValue == "Koi swimming")
        _ = model.step(KoiPondTuning.fixedStep)
        let burst = model.fish[0].head.distance(to: before)
        #expect(burst > KoiPondTuning.lapSpeed * KoiPondTuning.fixedStep * 2)
        expectSpine(model)
        let events = pump(&model, seconds: KoiPondTuning.scatterDuration + KoiPondTuning.returnTimeout + 0.4)
        #expect(events.contains(.returned))
        #expect(model.phase == .laps)
        #expect(model.fish.allSatisfy { $0.mode == .lap })
        expectSpine(model)
    }

    @Test func reduceMotionDriftsWithoutAScatterBurstAndFadesRipples() {
        var calm = KoiPondModel(seed: 15, reduceMotion: true)
        var wild = KoiPondModel(seed: 15, reduceMotion: false)
        let calmStart = calm.fish[0].head
        let wildStart = wild.fish[0].head
        _ = pump(&calm, seconds: 1)
        _ = pump(&wild, seconds: 1)
        let calmTravel = calm.fish[0].head.distance(to: calmStart)
        let wildTravel = wild.fish[0].head.distance(to: wildStart)
        #expect(calmTravel > 1)
        #expect(calmTravel < wildTravel * 0.75)

        calm.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&calm, seconds: KoiPondTuning.longPress + 0.3)
        let ripple = calm.ripples.first { $0.kind == .gather }
        #expect(ripple?.reduceMotion == true)
        let radius = ripple?.radius ?? -1
        let opacity = ripple?.opacity ?? -1
        _ = pump(&calm, seconds: 0.35)
        let later = calm.ripples.first { $0.kind == .gather }
        #expect(later != nil)
        #expect(near(later?.radius ?? -1, radius, 1e-6))
        #expect((later?.opacity ?? 1) < opacity)

        _ = pump(&calm, seconds: 9)
        #expect(calm.fish.allSatisfy { $0.mode == .nibbling })
        #expect(calm.arrivalOrder == Array(0..<calm.koiCount))
        let parked = calm.fish.map(\.head)
        let released = calm.endTouch()
        #expect(released == [.released])
        #expect(calm.phase == .returning)
        #expect(calm.fish.allSatisfy { $0.mode != .scattering })
        _ = pump(&calm, seconds: 0.25)
        let drift = zip(parked, calm.fish.map(\.head)).map { $0.distance(to: $1) }.max() ?? 0
        #expect(drift > 0.2)
        #expect(drift < KoiPondTuning.lapSpeed * 0.25 * 0.8)
        let home = pump(&calm, seconds: KoiPondTuning.returnTimeout + 0.5)
        #expect(home.contains(.returned))
        #expect(calm.phase == .laps)
        #expect(calm.fish.allSatisfy { $0.mode == .lap })
        expectSpine(calm)
    }

    @Test func feedGathersAtTheMiddleThenLetsGo() {
        var model = KoiPondModel(seed: 2)
        model.feed()
        #expect(model.phase == .gathering)
        #expect(model.holding)
        #expect(near(model.finger.x, KoiPondTuning.feedPoint.x))
        #expect(near(model.finger.y, KoiPondTuning.feedPoint.y))
        #expect(model.fish[0].mode == .seeking || model.fish[0].mode == .waiting || model.fish[0].mode == .nibbling || model.gatherTime == 0)
        _ = pump(&model, seconds: KoiPondTuning.fixedStep)
        #expect(model.fish[0].mode != .lap)
        let events = pump(&model, seconds: KoiPondTuning.feedDuration + KoiPondTuning.fixedStep)
        #expect(events.contains(.released))
        #expect(!model.holding)
        #expect(model.phase == .scattering || model.phase == .returning || model.phase == .laps)
    }

    @Test func ripplesDieAndAMovingFingerIsFollowed() {
        var model = KoiPondModel(seed: 6)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: KoiPondTuning.gatherLife + 0.05)
        #expect(!model.ripples.contains { $0.kind == .gather })
        let moved = Vec2(KoiPondTuning.feedPoint.x + 30, KoiPondTuning.feedPoint.y - 20)
        model.updateTouch(at: moved)
        #expect(model.finger.distance(to: KoiPondTuning.clampFinger(moved)) < 1e-6)
        _ = pump(&model, seconds: 6)
        #expect(model.fish.allSatisfy { $0.mode == .nibbling })
        #expect(model.fish.allSatisfy { $0.head.distance(to: model.finger) <= KoiPondTuning.nibbleGap + 0.5 })
    }

    @Test func aMovedFingerDoesNotTeleportANibblingKoi() {
        var model = KoiPondModel(seed: KoiPondTuning.defaultSeed)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: 8)
        #expect(model.fish[0].mode == .nibbling)
        let before = model.fish[0].head
        let relocated = Vec2(270, 550)
        model.updateTouch(at: relocated)
        let fingerMove = model.finger.distance(to: KoiPondTuning.feedPoint)
        #expect(fingerMove > 100)
        _ = model.step(KoiPondTuning.fixedStep)
        let jump = model.fish[0].head.distance(to: before)
        #expect(model.fish[0].mode == .seeking)
        #expect(jump < KoiPondTuning.seekSpeed * KoiPondTuning.fixedStep * 1.5)
        #expect(jump < fingerMove * 0.25)
        expectSpine(model)

        var calm = KoiPondModel(seed: KoiPondTuning.defaultSeed, reduceMotion: true)
        calm.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&calm, seconds: 12)
        #expect(calm.fish[0].mode == .nibbling)
        let calmBefore = calm.fish[0].head
        calm.updateTouch(at: relocated)
        _ = calm.step(KoiPondTuning.fixedStep)
        let calmJump = calm.fish[0].head.distance(to: calmBefore)
        #expect(calm.fish[0].mode == .seeking)
        #expect(calmJump < KoiPondTuning.seekSpeed * KoiPondTuning.reduceScale * KoiPondTuning.fixedStep * 1.5)
        expectSpine(calm)
    }

    @Test func reduceMotionFeedLastsUntilEveryKoiHasPecked() {
        var calm = KoiPondModel(reduceMotion: true)
        calm.feed()
        let early = pump(&calm, seconds: 4)
        let earlyNibbles = early.compactMap { event -> Int? in
            if case .nibble(let index) = event { return index }
            return nil
        }
        #expect(!early.contains(.released))
        #expect(calm.holding)
        #expect(earlyNibbles.count < calm.koiCount)

        let rest = pump(&calm, seconds: KoiPondTuning.feedCap)
        let nibbles = (early + rest).compactMap { event -> Int? in
            if case .nibble(let index) = event { return index }
            return nil
        }
        #expect(Set(nibbles) == Set(0..<calm.koiCount))
        #expect(rest.contains(.released))
        #expect(!calm.holding)
        expectSpine(calm)

        var wild = KoiPondModel(reduceMotion: false)
        wild.feed()
        let events = pump(&wild, seconds: KoiPondTuning.feedDuration + KoiPondTuning.fixedStep)
        let wildNibbles = events.compactMap { event -> Int? in
            if case .nibble(let index) = event { return index }
            return nil
        }
        #expect(Set(wildNibbles).count == wild.koiCount)
        #expect(events.contains(.released))
    }

    @Test func turningReduceMotionOnDropsAScatterBurst() {
        var model = KoiPondModel(seed: 9)
        model.beginTouch(at: KoiPondTuning.feedPoint)
        _ = pump(&model, seconds: 2.2)
        model.endTouch()
        #expect(model.phase == .scattering)
        model.setReduceMotion(true)
        #expect(model.phase == .returning)
        #expect(model.fish.allSatisfy { $0.mode != .scattering })
        _ = pump(&model, seconds: 0.2)
        expectSpine(model)
    }
}

private func wave(_ fish: KoiFish, at time: Double) -> Double {
    let posed = fish.posedSpine(at: time)
    let base = KoiPondMath.atan2(fish.spine[4].y - fish.spine[3].y, fish.spine[4].x - fish.spine[3].x)
    let bent = KoiPondMath.atan2(posed[4].y - posed[3].y, posed[4].x - posed[3].x)
    return KoiPondMath.wrap(bent - base)
}
