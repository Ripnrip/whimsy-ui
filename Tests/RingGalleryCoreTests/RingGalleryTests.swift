import Foundation
import Testing
@testable import RingGalleryCore

/// Steps `model` at 60 fps for up to `seconds`, calling `each` after every frame.
@discardableResult
private func run(_ model: inout RingGalleryModel, _ seconds: Double,
                 _ each: (RingGalleryModel) -> Void = { _ in }) -> RingGalleryModel {
    for _ in 0..<Int((seconds * 60).rounded()) { model.step(1.0 / 60); each(model) }
    return model
}

/// Drags by `distance` points over `duration` seconds in 60 fps samples, then releases with
/// `velocity` (nil = use the tracked speed).
private func fling(_ model: inout RingGalleryModel, distance: Double, duration: Double = 0.1,
                   velocity: Double? = nil) {
    model.dragBegan()
    let frames = max(1, Int((duration * 60).rounded()))
    for f in 1...frames {
        model.dragChanged(translation: distance * Double(f) / Double(frames), time: Double(f) / 60)
    }
    model.dragEnded(velocity: velocity)
}

private func isMultiple(_ r: Double, of s: Double) -> Bool {
    abs(r / s - (r / s).rounded()) < 1e-9
}

@Suite("Ring placement")
struct PlacementTests {
    @Test func frontCardIsCentredFullSizeAndOnTop() {
        let m = RingGalleryModel()
        let p = m.placement(for: 0)
        #expect(p.isFront)
        #expect(abs(p.angle) < 1e-12)
        #expect(abs(p.x) < 1e-9 && abs(p.y) < 1e-9)
        #expect(p.depth == 1 && p.scale == 1 && p.opacity == 1 && p.blur == 0)
        #expect(abs(p.yawDegrees) < 1e-9)
        let others = m.placements.dropFirst()
        #expect(others.allSatisfy { $0.zIndex < p.zIndex && !$0.isFront })
    }

    @Test func cardDirectlyBehindIsSmallestFaintestBlurriestAndHighest() {
        let m = RingGalleryModel(count: 8)
        let back = m.placement(for: 4)
        let t = RingGalleryModel.Tuning.default
        #expect(abs(abs(back.angle) - .pi) < 1e-9)
        #expect(back.depth < 1e-12)
        #expect(abs(back.scale - t.farScale) < 1e-9)
        #expect(abs(back.opacity - t.farOpacity) < 1e-9)
        #expect(abs(back.blur - t.maxBlur) < 1e-9)
        #expect(abs(back.y + t.elevation) < 1e-9)
        #expect(abs(back.yawDegrees) < 1e-6) // faces forward again: no mirrored card backs
        for p in m.placements where p.index != 4 {
            #expect(p.zIndex > back.zIndex)
            #expect(p.scale > back.scale && p.blur < back.blur)
        }
    }

    @Test func mirroredNeighboursAreSymmetric() {
        let m = RingGalleryModel(count: 8)
        for i in 1...3 {
            let a = m.placement(for: i), b = m.placement(for: 8 - i)
            #expect(abs(a.x + b.x) < 1e-9)
            #expect(abs(a.yawDegrees + b.yawDegrees) < 1e-9)
            #expect(abs(a.scale - b.scale) < 1e-12)
            #expect(abs(a.opacity - b.opacity) < 1e-12)
            #expect(abs(a.blur - b.blur) < 1e-12)
            #expect(abs(a.y - b.y) < 1e-9)
        }
        #expect(m.placement(for: 1).x > 0) // card 1 waits on the right
        #expect(m.placement(for: 1).yawDegrees > 0)
    }

    @Test func depthMonotonicallyFallsAwayFromTheFront() {
        let m = RingGalleryModel(count: 8)
        let byDistance = [0, 1, 2, 3, 4].map { m.placement(for: $0) }
        for (near, far) in zip(byDistance, byDistance.dropFirst()) {
            #expect(near.depth > far.depth)
            #expect(near.scale > far.scale)
            #expect(near.opacity > far.opacity)
            #expect(near.blur < far.blur)
        }
    }

    @Test func anglesAreEvenlySpacedAndWrapped() {
        let m = RingGalleryModel(count: 8)
        for p in m.placements {
            #expect(p.angle > -.pi && p.angle <= .pi)
        }
        #expect(abs(m.placement(for: 2).angle - .pi / 2) < 1e-12)
        #expect(abs(m.placement(for: 6).angle + .pi / 2) < 1e-12)
        #expect(abs(m.placement(for: 2).x - RingGalleryModel.Tuning.default.radius) < 1e-9)
    }

    @Test func wrapAngleCoversEdgeCases() {
        #expect(RingGalleryModel.wrapAngle(.pi) == .pi)
        #expect(abs(RingGalleryModel.wrapAngle(-.pi) - .pi) < 1e-12)
        #expect(abs(RingGalleryModel.wrapAngle(3 * .pi + 0.25) - (-.pi + 0.25)) < 1e-9)
        #expect(abs(RingGalleryModel.wrapAngle(-7 * .pi / 2) - .pi / 2) < 1e-9)
        #expect(RingGalleryModel.wrapAngle(.nan) == 0)
    }

    @Test func placementFollowsRotation() {
        // Rotating by exactly one spacing brings card 1 to where card 0 was.
        let s = 2 * Double.pi / 8
        let p = RingGalleryModel.placement(index: 1, count: 8, rotation: s)
        let q = RingGalleryModel.placement(index: 0, count: 8, rotation: 0)
        #expect(abs(p.x - q.x) < 1e-9 && abs(p.depth - q.depth) < 1e-12 && p.isFront)
    }

    @Test func countIsAtLeastOneAndASingleCardIsAlwaysFront() {
        var m = RingGalleryModel(count: 0)
        #expect(m.count == 1)
        #expect(m.placement(for: 0).isFront)
        fling(&m, distance: -300, velocity: -2000)
        run(&m, 4)
        #expect(m.frontIndex == 0)
        #expect(m.isSettled)
    }
}

@Suite("Drag, momentum and snap")
struct MotionTests {
    @Test func draggingRightTurnsCardsToTheRight() {
        var m = RingGalleryModel()
        m.dragBegan()
        m.dragChanged(translation: 30, time: 0.1)
        #expect(m.phase == .dragging)
        #expect(m.rotation < 0)
        #expect(m.placement(for: 0).x > 0) // the front card followed the finger
    }

    @Test func dragOfOneCardWidthAdvancesOneCard() {
        var m = RingGalleryModel()
        let per = RingGalleryModel.Tuning.default.dragPerCard
        m.dragBegan()
        m.dragChanged(translation: -per, time: 0.5)
        #expect(abs(m.position - 1) < 1e-9)
        #expect(m.frontIndex == 1)
        m.dragChanged(translation: per * 2, time: 1.0)
        #expect(m.frontIndex == 6) // two cards the other way from 0, wrapped
    }

    @Test func slowReleaseSnapsToNearestCardExactly() {
        var m = RingGalleryModel()
        m.dragBegan()
        m.dragChanged(translation: -0.4 * 120, time: 0.2)
        m.dragEnded(velocity: 0)
        #expect(m.phase == .snapping)
        run(&m, 2)
        #expect(m.isSettled)
        #expect(m.rotation == 0)
        #expect(m.frontIndex == 0)

        m.dragBegan()
        m.dragChanged(translation: -0.6 * 120, time: 0.2)
        m.dragEnded(velocity: 0)
        run(&m, 2)
        #expect(m.frontIndex == 1)
        #expect(isMultiple(m.rotation, of: m.spacing))
    }

    @Test func flingCoastsWithDecayingVelocityThenSnaps() {
        var m = RingGalleryModel()
        fling(&m, distance: -60, velocity: -1500)
        #expect(m.phase == .coasting)
        var speeds: [Double] = []
        var phases: [RingMotionPhase] = []
        run(&m, 4) { speeds.append(abs($0.angularVelocity)); phases.append($0.phase) }
        let coast = zip(speeds, phases).filter { $0.1 == .coasting }.map(\.0)
        #expect(coast.count > 10)
        #expect(zip(coast, coast.dropFirst()).allSatisfy { $1 < $0 }) // strictly decaying
        #expect(phases.contains(.snapping))
        #expect(m.isSettled)
        #expect(isMultiple(m.rotation, of: m.spacing))
    }

    @Test func harderFlingTravelsFurther() {
        func travel(_ v: Double) -> Double {
            var m = RingGalleryModel()
            fling(&m, distance: -40, velocity: v)
            run(&m, 5)
            #expect(m.isSettled)
            return m.position
        }
        let soft = travel(-400), medium = travel(-1200), hard = travel(-2400)
        #expect(soft < medium && medium < hard)
        #expect(soft >= 1)
        #expect(hard >= 3)
    }

    @Test func flingDirectionMatchesDragDirection() {
        var left = RingGalleryModel(), right = RingGalleryModel()
        fling(&left, distance: -50, velocity: -1800)
        fling(&right, distance: 50, velocity: 1800)
        run(&left, 5); run(&right, 5)
        #expect(left.position > 0 && right.position < 0)
        #expect(abs(left.position + right.position) < 1e-9) // symmetric
    }

    @Test func coastLandsOnItsProjectedTarget() {
        var m = RingGalleryModel()
        fling(&m, distance: -30, velocity: -2200)
        let projected = m.snapTarget
        run(&m, 5)
        #expect(abs(m.rotation - projected) < 1e-9)
    }

    @Test func trackedVelocityIsUsedWhenNoneIsGiven() {
        var m = RingGalleryModel()
        fling(&m, distance: -200, duration: 0.1) // 2000 pt/s
        #expect(m.phase == .coasting)
        #expect(m.angularVelocity > 0)
        run(&m, 5)
        #expect(m.position >= 2)
    }

    @Test func flingSpeedIsCapped() {
        var m = RingGalleryModel()
        fling(&m, distance: -10, velocity: -1e9)
        let t = RingGalleryModel.Tuning.default
        #expect(abs(m.angularVelocity - t.maxSpeed * m.spacing) < 1e-9)
    }

    @Test func snapOvershootIsSmall() {
        var m = RingGalleryModel()
        fling(&m, distance: -40, velocity: -2500)
        var maxOver = 0.0
        run(&m, 5) { s in
            if s.phase == .snapping || s.phase == .idle {
                maxOver = max(maxOver, (s.rotation - s.snapTarget) / s.spacing)
            }
        }
        #expect(maxOver < 0.15)
    }

    @Test func touchCatchesASpinningRing() {
        var m = RingGalleryModel()
        fling(&m, distance: -40, velocity: -2500)
        run(&m, 0.2)
        let caught = m.rotation
        m.dragBegan()
        #expect(m.angularVelocity == 0)
        run(&m, 0.5)
        #expect(m.rotation == caught)
        #expect(m.phase == .dragging)
    }

    @Test func cancelSnapsBackToNearest() {
        var m = RingGalleryModel()
        m.dragBegan()
        m.dragChanged(translation: -0.3 * 120, time: 0.1)
        m.dragCancelled()
        run(&m, 2)
        #expect(m.rotation == 0 && m.isSettled)
    }

    @Test func stepIgnoresBadTimestepsAndClampsHugeOnes() {
        var m = RingGalleryModel()
        fling(&m, distance: -40, velocity: -1500)
        let before = m
        m.step(.nan); m.step(-1); m.step(0); m.step(.infinity)
        #expect(m == before)
        m.step(10)
        #expect(abs(m.time - 0.1) < 1e-9)
    }
}

@Suite("Programmatic moves and Reduce Motion")
struct ProgrammaticTests {
    @Test func stepByOneAdvancesAndWraps() {
        var m = RingGalleryModel(count: 8)
        m.step(by: 1)
        run(&m, 2)
        #expect(m.frontIndex == 1 && m.isSettled)
        m.step(by: -2)
        run(&m, 2)
        #expect(m.frontIndex == 7)
        for _ in 0..<9 { m.step(by: 1) } // queued: targets accumulate
        run(&m, 4)
        #expect(m.frontIndex == 0)
    }

    @Test func selectTakesTheShortWayRound() {
        var m = RingGalleryModel(count: 8)
        m.select(7)
        #expect(abs(m.snapTarget + m.spacing) < 1e-12) // one card back, not seven forward
        run(&m, 2)
        #expect(m.frontIndex == 7)
        m.select(2)
        run(&m, 2)
        #expect(m.frontIndex == 2)
        #expect(abs(m.position - 2) < 1e-9) // 7 → 2 went forward three, not back five
    }

    @Test func reduceMotionNeverCoastsAndSnapsInstantly() {
        var m = RingGalleryModel(reduceMotion: true)
        m.dragBegan()
        m.dragChanged(translation: -0.7 * 120, time: 0.1)
        m.dragEnded(velocity: -5000)
        #expect(m.isSettled)
        #expect(m.frontIndex == 1) // nearest to where the finger let go, no momentum
        #expect(m.angularVelocity == 0)
        m.step(by: 1)
        #expect(m.isSettled && m.frontIndex == 2)
        m.select(5)
        #expect(m.isSettled && m.frontIndex == 5)
    }

    @Test func frontIndexHandlesNegativeAndLargeRotations() {
        var m = RingGalleryModel(count: 8)
        m.dragBegan()
        m.dragChanged(translation: 120 * 17, time: 0.1) // 17 cards backwards
        #expect(m.frontIndex == 7)
        m.dragChanged(translation: -120 * 803, time: 0.2)
        #expect(m.frontIndex == 3)
    }

    @Test func onlyOneCardIsFrontAtAnyRotation() {
        for k in 0..<64 {
            let r = Double(k) * 0.1 - 3
            let fronts = (0..<8).filter { RingGalleryModel.placement(index: $0, count: 8, rotation: r).isFront }
            #expect(fronts.count == 1)
        }
    }
}

@Suite("Film grain clock")
struct GrainTests {
    @Test func framesAreQuantisedToTwelvePerSecond() {
        #expect(RingGalleryModel.grainFrame(at: 0) == 0)
        #expect(RingGalleryModel.grainFrame(at: 1.0 / 12 - 1e-6) == 0)
        #expect(RingGalleryModel.grainFrame(at: 1.0 / 12) == 1)
        #expect(RingGalleryModel.grainFrame(at: 1.0) == 12)
        #expect(RingGalleryModel.grainFrame(at: 5.0 / 12) == 5) // exact multiples land correctly
        let frames = Set(stride(from: 0.0, to: 1.0, by: 1.0 / 120).map { RingGalleryModel.grainFrame(at: $0) })
        #expect(frames.count == 12)
    }

    @Test func seedHoldsWithinAFrameAndJumpsBetweenFrames() {
        let a = RingGalleryModel.grainSeed(at: 10.001), b = RingGalleryModel.grainSeed(at: 10.08)
        let c = RingGalleryModel.grainSeed(at: 10.09)
        #expect(a == b)
        #expect(b != c)
        // Large absolute times (TimelineView dates) still quantise.
        let t = 8e8
        #expect(RingGalleryModel.grainFrame(at: t + 0.01) == RingGalleryModel.grainFrame(at: t + 0.02))
    }

    @Test func seedsAreDeterministicUniformAndDecorrelated() {
        let seeds = (0..<1200).map { RingGalleryModel.grainSeed(frame: $0) }
        #expect(seeds == (0..<1200).map { RingGalleryModel.grainSeed(frame: $0) })
        #expect(seeds.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = seeds.reduce(0, +) / Double(seeds.count)
        #expect(abs(mean - 0.5) < 0.04)
        let steps = zip(seeds, seeds.dropFirst()).map { abs($1 - $0) }
        #expect(steps.reduce(0, +) / Double(steps.count) > 0.25) // neighbours unrelated (~1/3)
        #expect(RingGalleryModel.grainSeed(frame: -3) != RingGalleryModel.grainSeed(frame: 3))
    }

    @Test func reduceMotionFreezesTheGrain() {
        let seeds = Set(stride(from: 0.0, to: 3.0, by: 0.05).map {
            RingGalleryModel.grainSeed(at: $0, reduceMotion: true)
        })
        #expect(seeds.count == 1)
        #expect(RingGalleryModel.grainFrame(at: 99, reduceMotion: true) == 0)
        #expect(RingGalleryModel.grainFrame(at: .nan) == 0)
    }
}
