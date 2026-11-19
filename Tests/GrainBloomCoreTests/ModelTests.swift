import Testing
@testable import GrainBloomCore

@Suite("Grain bloom model") struct GrainBloomModelTests {
    @Test func generatingFromIdleWakes() {
        var model = GrainBloomModel()
        #expect(model.phase == .idle)
        model.setGenerating(true)
        model.step(0.05)
        #expect(model.phase == .waking)
        #expect(model.accessibilityValue == GrainBloomTuning.generatingValue)
    }

    @Test func imageDuringWakingStartsResolving() {
        var model = GrainBloomModel(generating: true)
        #expect(model.phase == .waking)
        model.step(0.1)
        model.setImagePresent(true)
        #expect(model.phase == .resolving)
    }

    @Test func resolvingReachesDoneWithFullCoverage() {
        var model = GrainBloomModel(generating: true, hasImage: true)
        #expect(model.phase == .resolving)
        model.step(GrainBloomTuning.resolveDuration)
        #expect(model.phase == .done)
        #expect(model.revealCoverage == 1)
        #expect(model.accessibilityValue == GrainBloomTuning.readyValue)
        #expect(model.playsSettle)
    }

    @Test func replayWaitsOutTheWakeThenResolvesAgain() {
        var model = finished()
        let replayed = model.replay()
        #expect(replayed)
        #expect(model.phase == .waking)
        #expect(model.hasImage)
        model.step(GrainBloomTuning.wakeDuration * 0.4)
        #expect(model.phase == .waking)
        model.step(GrainBloomTuning.wakeDuration)
        #expect(model.phase == .resolving)
        model.step(GrainBloomTuning.resolveDuration)
        #expect(model.phase == .done)
        #expect(model.revealCoverage == 1)
    }

    @Test func replayIsIgnoredUntilDone() {
        var waking = GrainBloomModel(generating: true)
        let wakingReplay = waking.replay()
        #expect(!wakingReplay)
        #expect(waking.phase == .waking)
        var resolving = GrainBloomModel(generating: true, hasImage: true)
        let resolvingReplay = resolving.replay()
        #expect(!resolvingReplay)
        #expect(resolving.phase == .resolving)
    }

    @Test func cancellingGenerationReturnsToIdle() {
        var model = GrainBloomModel(generating: true)
        #expect(model.phase == .waking)
        model.setGenerating(false)
        #expect(model.phase == .idle)
        #expect(!model.hasImage)
    }

    @Test func mountedPictureWithoutGenerationRestsDone() {
        let model = GrainBloomModel(generating: false, hasImage: true)
        #expect(model.phase == .done)
        #expect(model.phaseTime == 0)
        #expect(!model.playsSettle)
        #expect(model.glint == 0)
    }

    @Test func mountedGeneratingWithoutPictureWakes() {
        let model = GrainBloomModel(generating: true, hasImage: false)
        #expect(model.phase == .waking)
    }

    @Test func mountedGeneratingWithPictureResolves() {
        let model = GrainBloomModel(generating: true, hasImage: true)
        #expect(model.phase == .resolving)
    }

    @Test func generatingAgainAfterDoneStaysDone() {
        var model = finished()
        model.setGenerating(false)
        model.setGenerating(true)
        #expect(model.phase == .done)
        #expect(model.hasImage)
    }

    @Test func clearingAndReturningThePictureRestartsResolve() {
        var model = finished()
        let epoch = model.epoch
        model.setImagePresent(false)
        #expect(model.phase == .idle)
        model.setImagePresent(true)
        #expect(model.phase == .resolving)
        #expect(model.epoch == epoch + 2)
        #expect(model.resolveProgress == 0)
    }

    @Test func clearingWhileGeneratingWakes() {
        var model = finished(generating: true)
        model.setImagePresent(false)
        #expect(model.phase == .waking)
        #expect(model.isGenerating)
    }

    @Test func twoSeedsWithTheSameEventsMatch() {
        let left = scripted(seed: 42)
        let right = scripted(seed: 42)
        #expect(left.phase == right.phase)
        #expect(left.resolveProgress == right.resolveProgress)
        #expect(left.revealCoverage == right.revealCoverage)
        #expect(left.blob(0).x == right.blob(0).x)
    }

    @Test func reduceMotionCrossfadesWithoutTheCellLadder() {
        var model = GrainBloomModel(reduceMotion: true)
        model.setImagePresent(true)
        let size = model.cellSize
        #expect(size == 16)
        model.step(GrainBloomTuning.reduceDuration / 2)
        #expect(model.cellSize == size)
        #expect(model.phase == .resolving)
        let early = GrainBloomMath.dotScale(wakeTime: 0, delay: 0.2, reduceMotion: true)
        let later = GrainBloomMath.dotScale(wakeTime: 0.7, delay: 0.2, reduceMotion: true)
        #expect(later == early)
        model.step(GrainBloomTuning.reduceDuration)
        #expect(model.revealCoverage == 1)
        #expect(model.phase == .done)
        #expect(model.cellSize == size)
    }

    @Test func reduceMotionMidResolveDoesNotDropCoverage() {
        var model = GrainBloomModel(generating: true, hasImage: true)
        model.step(GrainBloomTuning.resolveDuration * 0.45)
        let before = model.revealCoverage
        model.setReduceMotion(true)
        #expect(model.revealCoverage >= before)
        model.step(0.05)
        #expect(model.revealCoverage >= before)
    }

    private func finished(generating: Bool = false) -> GrainBloomModel {
        var model = GrainBloomModel(generating: true, hasImage: true)
        model.step(GrainBloomTuning.resolveDuration)
        if !generating { model.setGenerating(false) }
        return model
    }

    private func scripted(seed: UInt64) -> GrainBloomModel {
        var model = GrainBloomModel(seed: seed)
        model.setGenerating(true)
        model.step(0.2)
        model.setImagePresent(true)
        model.step(0.3)
        return model
    }
}
