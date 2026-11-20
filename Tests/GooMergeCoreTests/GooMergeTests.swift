import Foundation
import Testing
@testable import GooMergeCore

extension GooMergeModel {
    @discardableResult
    mutating func run(_ seconds: Double) -> [GooMergeEvent] {
        var out: [GooMergeEvent] = []
        var left = seconds
        while left > 1e-12 {
            let h = min(left, 1.0 / 60.0)
            out += step(h)
            left -= h
        }
        return out
    }
}

private func between(_ model: GooMergeModel, gap: Double) -> Vec2 {
    let a = model.bodies[0].home
    let b = model.bodies[1].home
    let reach = model.bodies[0].radius + model.bodies[1].radius + gap
    return b + (a - b).normalized * reach
}

private func mergedName(_ events: [GooMergeEvent]) -> [String] {
    events.compactMap { event in
        if case .merged(let name) = event { return name }
        return nil
    }
}

@Suite("Field and ring") struct GooMergeFieldTests {
    @Test func radiusFollowsTheValueAndClamps() {
        #expect(GooMergeField.radius(for: 0) == GooMergeTuning.minRadius)
        #expect(GooMergeField.radius(for: 1) == GooMergeTuning.maxRadius)
        #expect(GooMergeField.radius(for: 2) == GooMergeTuning.maxRadius)
        #expect(GooMergeField.radius(for: -4) == GooMergeTuning.minRadius)
        #expect(GooMergeField.radius(for: .nan) == GooMergeTuning.minRadius)
        let low = GooMergeField.radius(for: 0.48)
        let high = GooMergeField.radius(for: 0.84)
        #expect(low > GooMergeTuning.minRadius)
        #expect(high > low)
        #expect(high < GooMergeTuning.maxRadius)
    }

    @Test func smoothMinMatchesThePolynomial() {
        #expect(GooMergeField.smoothMin(3, 5, 0) == 3)
        #expect(GooMergeField.smoothMin(5, 3, -2) == 3)
        #expect(GooMergeField.smoothMin(4, 4, 8) == 2)
        #expect(GooMergeField.smoothMin(1, 9, 2) == 1)
    }

    @Test func metaballGrowsAsACircleApproaches() {
        let far = GooMergeField.metaball(at: .zero, circles: [GooCircle(center: Vec2(30, 0), radius: 8)])
        let near = GooMergeField.metaball(at: .zero, circles: [GooCircle(center: Vec2(6, 0), radius: 8)])
        #expect(near > far)
        #expect(far > 0)
    }

    @Test func fiveSamplesSitOnAnEvenRingAroundTheWell() {
        let model = GooMergeModel()
        #expect(model.count == 5)
        #expect(model.drops.map(\.name) == ["brief.md", "shot.png", "notes.txt", "reel.mov", "deck.key"])
        #expect(model.phase == .ready)
        #expect(model.mergeProgress == 0)
        let step = cos(2 * Double.pi / 5)
        for body in model.bodies {
            #expect(abs(body.home.distance(to: model.well) - GooMergeTuning.ringRadius) < 1e-9)
            #expect(body.center == body.home)
            #expect(body.renderCenter == body.home)
            #expect(body.stretch == 0)
            #expect(abs(body.radius - GooMergeField.radius(for: body.value)) < 1e-12)
        }
        #expect(abs(model.bodies[0].home.x - model.well.x) < 1e-9)
        #expect(model.bodies[0].home.y < model.well.y)
        for index in model.bodies.indices {
            let here = model.bodies[index].home - model.well
            let next = model.bodies[(index + 1) % model.count].home - model.well
            let dot = here.normalized.dot(next.normalized)
            #expect(abs(dot - step) < 1e-9)
        }
        #expect(model.sdf(at: model.well) > 0)
        #expect(model.connectedPairCount == 0)
        let stacked = model.drops.map { GooCircle(center: model.well, radius: GooMergeField.radius(for: $0.value)) }
        #expect(GooMergeField.sdf(at: model.well, circles: stacked) < 0)
    }

    @Test func fourDropsAndATrimmedListStillRing() {
        let four = [
            GooDrop(name: "a.txt", value: 0.4),
            GooDrop(name: "b.txt", value: 0.55),
            GooDrop(name: "c.txt", value: 0.7),
            GooDrop(name: "d.txt", value: 0.9),
        ]
        let model = GooMergeModel(drops: four, seed: 3)
        #expect(model.count == 4)
        #expect(model.bodies.map(\.name) == ["a.txt", "b.txt", "c.txt", "d.txt"])
        #expect(model.bodies[0].radius < model.bodies[3].radius)
        let right = cos(2 * Double.pi / 4)
        for index in model.bodies.indices {
            let home = model.bodies[index].home
            #expect(home.distance(to: GooMergeField.ringPoint(index: index, count: 4)) < 1e-9)
            let here = home - model.well
            let next = model.bodies[(index + 1) % 4].home - model.well
            #expect(abs(here.normalized.dot(next.normalized) - right) < 1e-9)
        }
        let extra = four + [GooDrop(name: "e.txt", value: 0.2), GooDrop(name: "f.txt", value: 0.3)]
        #expect(GooMergeModel(drops: extra).count == 5)
        #expect(GooMergeModel(drops: extra).drops.map(\.name) == ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"])
        #expect(GooMergeModel(drops: []).drops.map(\.id) == GooDrop.samples.map(\.id))
        #expect(GooMergeModel(drops: [GooDrop(name: "only.txt", value: 1)]).count == 5)
    }
}

@Suite("Stretch and snap") struct GooMergeDragTests {
    @Test func aWideGapDoesNotStretch() {
        var model = GooMergeModel(seed: 2)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        let events = model.updateDrag(to: between(model, gap: 72))
        #expect(events.isEmpty)
        #expect(model.stretch(of: 0) == 0)
        #expect(model.stretch(of: 1) == 0)
        #expect(!model.isSnapped(0, 1))
    }

    @Test func insideTheBandBothDropsStretchAndDoNotSnap() {
        var model = GooMergeModel(seed: 2)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        let gap = (GooMergeTuning.stretchReach + GooMergeTuning.snapGap) / 2
        let events = model.updateDrag(to: between(model, gap: gap))
        #expect(events.isEmpty)
        #expect(!model.isSnapped(0, 1))
        #expect(model.stretch(of: 0) > 0.4)
        #expect(model.stretch(of: 0) < 0.6)
        #expect(model.stretch(of: 1) > 0.4)
        let dragged = model.bodies[0]
        let other = model.bodies[1]
        let toward = (other.center - dragged.center).normalized
        let shift = dragged.renderCenter - dragged.center
        #expect(shift.dot(toward) > 4)
        let back = (dragged.center - other.center).normalized
        #expect((other.renderCenter - other.center).dot(back) > 4)
        #expect(model.bodies[2].stretch == 0)
    }

    @Test func crossingTheSnapGapJoinsThePair() {
        var model = GooMergeModel(seed: 2)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        let events = model.updateDrag(to: between(model, gap: GooMergeTuning.snapGap * 0.5))
        #expect(events.contains(.snapped(0, 1)))
        #expect(events.contains(.haptic))
        #expect(model.isSnapped(0, 1))
        #expect(model.bodies[0].center.distance(to: model.bodies[1].center) < 1e-9)
        #expect(model.stretch(of: 0) == 0)
        #expect(model.stretch(of: 1) == 0)
        #expect(model.bodies[0].cluster == model.bodies[1].cluster)
    }

    @Test func aMissedHitDoesNothingAndAHomeHitGrabsThatDrop() {
        var model = GooMergeModel(seed: 1)
        #expect(model.hitIndex(at: Vec2(12, 12)) == nil)
        let missed = model.beginDrag(at: Vec2(12, 12))
        #expect(!missed)
        #expect(!model.isDragging)
        let home = model.bodies[3].home
        #expect(model.hitIndex(at: home) == 3)
        let grabbedHome = model.beginDrag(at: home)
        #expect(grabbedHome)
        #expect(model.isDragging)
        let stayed = model.updateDrag(to: home)
        #expect(stayed.isEmpty)
    }

    @Test func lettingGoOfAnUnsnappedDropSpringsItHome() {
        var model = GooMergeModel(seed: 5)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        let away = Vec2(195, 150)
        _ = model.updateDrag(to: away)
        #expect(model.stretch(of: 0) == 0)
        #expect(!model.isSnapped(0, 1))
        _ = model.endDrag()
        let left = model.bodies[0].center.distance(to: model.bodies[0].home)
        #expect(left > 40)
        _ = model.run(1.6)
        #expect(model.bodies[0].center.distance(to: model.bodies[0].home) < 1.5)
        #expect(model.phase == .ready)
    }
}

@Suite("Combine") struct GooMergeCombineTests {
    @Test func everyDropReachesTheWell() {
        var model = GooMergeModel(seed: 8)
        let events = model.combine()
        #expect(events == [.combining])
        #expect(model.phase == .combining)
        let again = model.combine()
        #expect(again.isEmpty)
        var sawArrival = false
        var previous = model.bodies.map { $0.center.distance(to: model.well) }
        for _ in 0..<240 {
            let before = model.phase
            _ = model.step(1.0 / 60.0)
            let distances = model.bodies.map { $0.center.distance(to: model.well) }
            if before == .combining {
                for index in distances.indices {
                    #expect(distances[index] <= previous[index] + 1e-6)
                }
            }
            if before == .combining, model.phase == .morphing {
                sawArrival = true
                for distance in distances {
                    #expect(distance <= GooMergeTuning.arrival + 1e-6)
                }
            }
            previous = distances
        }
        #expect(sawArrival)
    }

    @Test func mergeProgressIsMonotonicAndCompletes() {
        var model = GooMergeModel(seed: 8)
        #expect(model.mergeProgress == 0)
        _ = model.combine()
        var previous = model.mergeProgress
        var previousMeta = model.metaball(at: model.well)
        #expect(previous < 0.02)
        var finished = false
        for _ in 0..<240 {
            _ = model.step(1.0 / 60.0)
            let next = model.mergeProgress
            #expect(next + 1e-8 >= previous)
            if model.phase == .combining {
                let meta = model.metaball(at: model.well)
                #expect(meta + 1e-7 >= previousMeta)
                previousMeta = meta
            }
            previous = next
            if model.phase == .morphing || model.phase == .merged {
                finished = true
                #expect(next == 1)
            }
        }
        #expect(finished)
        #expect(model.mergeProgress == 1)
        #expect(model.connectedPairCount == model.count * (model.count - 1) / 2)
    }

    @Test func theMorphReachesTheDocumentCard() {
        var model = GooMergeModel(seed: 8)
        var events = model.combine()
        events += model.run(GooMergeTuning.morphDuration + 2.4)
        #expect(model.phase == .merged)
        #expect(model.morphProgress == 1)
        #expect(model.cardOpacity == 1)
        #expect(model.blobOpacity == 0)
        #expect(model.fold == 1)
        #expect(model.documentName == "Binder-01.pdf")
        #expect(mergedName(events) == ["Binder-01.pdf"])
        #expect(model.accessibilityValue == GooMergeTuning.mergedValue)
    }

    @Test func aSnappedPairStillPoursIntoTheWell() {
        var model = GooMergeModel(seed: 4)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        _ = model.updateDrag(to: between(model, gap: 4))
        #expect(model.isSnapped(0, 1))
        _ = model.endDrag()
        _ = model.combine()
        _ = model.run(2.2)
        #expect(model.phase == .morphing || model.phase == .merged)
        for body in model.bodies {
            #expect(body.center.distance(to: model.well) <= GooMergeTuning.arrival + 1e-6)
        }
    }
}

@Suite("Reduce Motion") struct GooMergeReduceMotionTests {
    @Test func draggingCloseDoesNotStretchOrSnap() {
        var model = GooMergeModel(seed: 2, reduceMotion: true)
        let grabbed = model.beginDrag(index: 0)
        #expect(grabbed)
        let events = model.updateDrag(to: between(model, gap: 4))
        #expect(events.isEmpty)
        #expect(model.stretch(of: 0) == 0)
        #expect(model.stretch(of: 1) == 0)
        #expect(!model.isSnapped(0, 1))
        #expect(model.bodies[0].renderCenter.distance(to: model.bodies[0].center) < 1e-9)
        #expect(!model.animates)
    }

    @Test func combineSnapsToTheWellAndCrossfadesToTheCard() {
        var model = GooMergeModel(seed: 6, reduceMotion: true)
        let started = model.combine()
        #expect(started.contains(.combining))
        #expect(started.contains(.morphing))
        #expect(model.phase == .morphing)
        #expect(model.mergeProgress == 1)
        #expect(model.morphProgress == 0)
        for body in model.bodies {
            #expect(body.center.distance(to: model.well) < 1e-9)
            #expect(body.stretch == 0)
        }
        let events = model.run(GooMergeTuning.reducedFade)
        #expect(model.phase == .merged)
        #expect(model.morphProgress == 1)
        #expect(model.cardOpacity == 1)
        #expect(model.blobOpacity == 0)
        #expect(mergedName(events) == ["Binder-01.pdf"])
        #expect(model.accessibilityLabel == "Goo merge, 5 files")
        #expect(model.accessibilityValue == "Merged into Binder-01.pdf")
    }

    @Test func theThreeSpokenStates() {
        var model = GooMergeModel()
        #expect(model.accessibilityLabel == "Goo merge, 5 files")
        #expect(model.accessibilityValue == "Ready to combine")
        _ = model.combine()
        #expect(model.accessibilityValue == "Merging")
        _ = model.run(3)
        #expect(model.accessibilityValue == "Merged into Binder-01.pdf")
        #expect(GooMergeTuning.combineAction == "Combine")
    }
}

@Suite("Clock") struct GooMergeClockTests {
    @Test func theSameSeedRepeatsAndAnotherSeedBobsDifferently() {
        func signature(_ seed: UInt64) -> [Double] {
            var model = GooMergeModel(seed: seed)
            _ = model.step(0.37)
            return model.bodies.flatMap { [$0.renderCenter.x, $0.renderCenter.y, $0.stretch] }
        }
        let one = signature(4)
        let again = signature(4)
        let other = signature(9)
        #expect(one == again)
        #expect(one != other)
        #expect(GooMergeModel(seed: 4).bobOmegas != GooMergeModel(seed: 9).bobOmegas)
        var left = GooMergeModel(seed: 4)
        var right = GooMergeModel(seed: 4)
        _ = left.combine()
        _ = right.combine()
        _ = left.run(1.25)
        _ = right.run(1.25)
        #expect(left.bodies.map(\.center) == right.bodies.map(\.center))
        #expect(left.mergeProgress == right.mergeProgress)
        #expect(left.phase == right.phase)
    }

    @Test func unusableStepsDoNothingAndALongFrameClamps() {
        var model = GooMergeModel(seed: 1)
        let before = model.bodies.map(\.center)
        let zero = model.step(0)
        let negative = model.step(-0.2)
        let nan = model.step(.nan)
        let infinite = model.step(.infinity)
        #expect(zero.isEmpty)
        #expect(negative.isEmpty)
        #expect(nan.isEmpty)
        #expect(infinite.isEmpty)
        #expect(model.time == 0)
        #expect(model.bodies.map(\.center) == before)

        var long = GooMergeModel(seed: 1)
        var clamped = GooMergeModel(seed: 1)
        _ = long.combine()
        _ = clamped.combine()
        _ = long.step(5)
        _ = clamped.step(GooMergeTuning.maxFrame)
        #expect(long.time == clamped.time)
        #expect(long.bodies.map(\.center) == clamped.bodies.map(\.center))
        #expect(long.mergeProgress == clamped.mergeProgress)
    }

    @Test func theMorphEaseIsMonotonic() {
        #expect(GooMergeModel.easeInOut(0) == 0)
        #expect(GooMergeModel.easeInOut(1) == 1)
        #expect(abs(GooMergeModel.easeInOut(0.5) - 0.5) < 1e-12)
        var previous = -1.0
        for step in 0...20 {
            let value = GooMergeModel.easeInOut(Double(step) / 20)
            #expect(value >= previous)
            previous = value
        }
    }
}
