import Testing
import Foundation
@testable import ContourInkCore

@Suite struct ContourHashTests {
    @Test func matchesLowbias32ReferenceValues() {
        let expected: [UInt32: UInt32] = [0: 0, 1: 1_753_845_952, 2: 3_507_691_905, 12345: 2_435_775_735,
                                          0xFFFF_FFFF: 1_734_902_346, 0x30C7: 2_749_836_933]
        for (k, v) in expected { #expect(ContourHash.hash32(k) == v) }
    }

    @Test func saltedValuesMatchReference() {
        let salts = [0, 1, 100, 307, 513]
        let expected: [UInt32] = [2_665_007_124, 4_212_481_260, 2_608_646_604, 358_405_668, 2_495_464_837]
        for (s, e) in zip(salts, expected) { #expect(ContourHash.value(0x30C7, s) == e) }
    }

    @Test func unitIsInHalfOpenRange() {
        #expect(abs(ContourHash.unit(ContourHash.hash32(7)) - 0.5454391241073608) < 1e-15)
        #expect(abs(ContourHash.unit(99, 5) - 0.1825910210609436) < 1e-15)
        for s in 0..<500 {
            let u = ContourHash.unit(UInt32(s), s * 3)
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func unitIsRoughlyUniform() {
        var buckets = [Int](repeating: 0, count: 10)
        for s in 0..<5000 { buckets[min(9, Int(ContourHash.unit(0xBEEF, s) * 10))] += 1 }
        for b in buckets { #expect(b > 380 && b < 620) }
    }

    @Test func differentSaltsGiveDifferentValues() {
        let vs = Set((0..<200).map { ContourHash.value(5, $0) })
        #expect(vs.count == 200)
    }
}

@Suite struct RingBuildingTests {
    @Test func countIsClamped() {
        #expect(ContourInkGeometry.clampedCount(0) == 3)
        #expect(ContourInkGeometry.clampedCount(-9) == 3)
        #expect(ContourInkGeometry.clampedCount(7) == 7)
        #expect(ContourInkGeometry.clampedCount(99) == 12)
        #expect(ContourMap.make(rings: 1).count == 3)
        #expect(ContourMap.make(rings: 50).count == 12)
        #expect(ContourMap.make().count == 7)
    }

    @Test func everyRingHasTheSampleCountAndAClosedLength() {
        for r in ContourMap.make().rings {
            #expect(r.points.count == ContourInkGeometry.sampleCount)
            #expect(r.cumulative.count == r.points.count + 1)
            #expect(r.cumulative[0] == 0)
            #expect(r.length > 0)
            let closing = r.points[r.points.count - 1].distance(to: r.points[0])
            #expect(abs((r.cumulative[r.points.count] - r.cumulative[r.points.count - 1]) - closing) < 1e-12)
        }
    }

    @Test func cumulativeLengthGrowsStrictly() {
        for r in ContourMap.make().rings {
            for i in 1..<r.cumulative.count { #expect(r.cumulative[i] > r.cumulative[i - 1]) }
        }
    }

    @Test func radiiShrinkFromTheOutsideIn() {
        let m = ContourMap.make()
        #expect(abs(m.rings[0].radius - ContourInkGeometry.outerRadius) < 1e-12)
        for k in 1..<m.count { #expect(m.rings[k].radius < m.rings[k - 1].radius) }
        let inner = ContourInkGeometry.outerRadius * (1 - ContourInkGeometry.innerShrink * 6.0 / 7.0)
        #expect(abs(m.rings[6].radius - inner) < 1e-12)
    }

    @Test func smallerRingsDriftTowardTheOffCentrePeak() {
        let m = ContourMap.make()
        #expect(m.rings[0].center == .zero)
        #expect(m.rings[6].center == ContourInkGeometry.peak)
        #expect(m.peak == ContourInkGeometry.peak)
        var prev = 0.0
        for r in m.rings {
            let d = r.center.length
            #expect(d >= prev)
            prev = d
            // always on the line from the middle toward the peak
            #expect(abs(r.center.cross(ContourInkGeometry.peak)) < 1e-12)
        }
        #expect(ContourInkGeometry.peak.length > 0.05)
    }

    @Test func peakIsOffCentreForEveryCount() {
        for n in 3...12 {
            let m = ContourMap.make(rings: n)
            #expect(m.peak == ContourInkGeometry.peak)
            #expect(m.rings[0].center == .zero)
        }
    }

    @Test func centreStepsGetLargerTowardThePeak() {
        let m = ContourMap.make()
        var steps: [Double] = []
        for k in 1..<m.count { steps.append(m.rings[k].center.distance(to: m.rings[k - 1].center)) }
        for i in 1..<steps.count { #expect(steps[i] > steps[i - 1]) }
    }

    @Test func indexContoursRepeatEveryThirdRing() {
        let m = ContourMap.make()
        #expect(m.rings.map(\.isIndex) == [true, false, false, true, false, false, true])
        let m6 = ContourMap.make(rings: 6)
        #expect(m6.rings.map(\.isIndex) == [true, false, false, true, false, false])
    }

    @Test func ringsStartTheirStrokeAtDifferentAngles() {
        let m = ContourMap.make()
        let angles = Set(m.rings.map { Int($0.startAngle * 1e6) })
        #expect(angles.count == m.count)
        for r in m.rings {
            #expect(r.startAngle >= 0 && r.startAngle < 2 * Double.pi)
            #expect(r.points[0].distance(to: r.point(atAngle: r.startAngle)) < 1e-12)
        }
    }

    @Test func pointsFollowTheAngleInOrder() {
        let r = ContourMap.make().rings[2]
        for i in 0..<r.points.count {
            let a = r.startAngle + 2 * Double.pi * Double(i) / Double(r.points.count)
            #expect(r.points[i].distance(to: r.point(atAngle: a)) < 1e-12)
        }
    }

    @Test func everyPointStaysOnTheSheet() {
        for n in 3...12 {
            for r in ContourMap.make(rings: n).rings {
                for p in r.points { #expect(abs(p.x) < 0.5 && abs(p.y) < 0.5) }
            }
        }
    }
}

@Suite struct ContourWobbleTests {
    @Test func theRadiusFactorStaysWithinTheAmplitudes() {
        for r in ContourMap.make().rings {
            let bound = r.amplitudes.reduce(0, +)
            for i in 0..<720 {
                let f = r.radialFactor(at: Double(i) * 0.01)
                #expect(abs(f - 1) <= bound + 1e-12)
            }
        }
    }

    @Test func amplitudesAreScaledFromTheBaseWithAJitter() {
        let r = ContourInkGeometry.ring(2, of: 7, seed: ContourInkGeometry.defaultSeed, wobble: 1)
        for (j, a) in r.amplitudes.enumerated() {
            let base = ContourInkGeometry.baseAmplitudes[j]
            #expect(a >= base * 0.85 && a <= base * 1.15)
        }
        let half = ContourInkGeometry.ring(2, of: 7, seed: ContourInkGeometry.defaultSeed, wobble: 0.5)
        for j in 0..<3 { #expect(abs(half.amplitudes[j] - r.amplitudes[j] / 2) < 1e-15) }
    }

    @Test func zeroWobbleGivesTruePerimeterCircles() {
        for k in 0..<7 {
            let r = ContourInkGeometry.ring(k, of: 7, seed: 9, wobble: 0)
            for p in r.points { #expect(abs(p.distance(to: r.center) - r.radius) < 1e-12) }
            #expect(abs(r.length - 2 * Double.pi * r.radius) < 0.002)
        }
    }

    @Test func theDefaultMapKeepsItsFullWobbleAndReallyWobbles() {
        let m = ContourMap.make()
        #expect(m.wobbleScale == 1)
        for r in m.rings {
            let ds = r.points.map { $0.distance(to: r.center) }
            let spread = (ds.max()! - ds.min()!) / r.radius
            #expect(spread > 0.06)
        }
    }

    @Test func phasesDriftFromRingToRingSoNeighboursResembleEachOther() {
        let m = ContourMap.make()
        for k in 1..<m.count {
            for j in 0..<3 {
                let d = m.rings[k].phases[j] - m.rings[k - 1].phases[j]
                #expect(d > 0.2 && d < 0.41)
            }
        }
    }

    @Test func theSameSeedGivesTheSameMap() {
        #expect(ContourMap.make(rings: 7, seed: 5) == ContourMap.make(rings: 7, seed: 5))
        #expect(ContourMap.make() == ContourMap.make(rings: 7, seed: ContourInkGeometry.defaultSeed))
    }

    @Test func differentSeedsGiveDifferentMaps() {
        let a = ContourMap.make(rings: 7, seed: 1), b = ContourMap.make(rings: 7, seed: 2)
        #expect(a != b)
        #expect(a.rings[3].points[10] != b.rings[3].points[10])
        #expect(a.rings[3].phases != b.rings[3].phases)
    }
}

@Suite struct NeverIntersectTests {
    @Test func minGapIsPositiveForTheDefaultMap() {
        let m = ContourMap.make()
        #expect(m.minGap > 0)
        #expect(m.minGap >= ContourInkGeometry.minGapFloor)
    }

    @Test func everyNeighbouringPairIsNestedWithAPositiveGap() {
        let m = ContourMap.make()
        for k in 0..<(m.count - 1) {
            let g = ContourInkGeometry.gap(outer: m.rings[k], inner: m.rings[k + 1])
            #expect(g > 0, "rings \(k) and \(k + 1)")
            for p in m.rings[k + 1].points { #expect(m.rings[k].contains(p)) }
        }
    }

    @Test func noTwoRingsAtAnyDistanceTouch() {
        let m = ContourMap.make()
        for a in 0..<m.count {
            for b in (a + 1)..<m.count {
                #expect(ContourInkGeometry.gap(outer: m.rings[a], inner: m.rings[b]) > 0, "rings \(a) and \(b)")
            }
        }
    }

    @Test func minGapHoldsForEveryCountAndManySeeds() {
        for n in 3...12 {
            for s in 0..<8 {
                let m = ContourMap.make(rings: n, seed: UInt32(s) &* 2_654_435_761 &+ 17)
                #expect(m.minGap >= ContourInkGeometry.minGapFloor, "n=\(n) seed=\(s) scale=\(m.wobbleScale)")
            }
        }
    }

    @Test func gapGrowsWhenFewerRingsAreSpreadOverTheSameHill() {
        // more rings are packed closer together
        let gaps = [3, 5, 7, 9, 12].map { ContourMap.make(rings: $0, seed: 3).minGap }
        for i in 1..<gaps.count { #expect(gaps[i] < gaps[i - 1]) }
    }

    @Test func wobbleIsTurnedDownWhenFullWobbleWouldGetTooClose() {
        // seed 1 at 7 rings needs the first step down
        let seed: UInt32 = 1
        let full = (0..<7).map { ContourInkGeometry.ring($0, of: 7, seed: seed, wobble: 1) }
        #expect(ContourMap.minGap(of: full) < ContourInkGeometry.minGapFloor)
        let m = ContourMap.make(rings: 7, seed: seed)
        #expect(m.wobbleScale == 0.85)
        #expect(m.minGap >= ContourInkGeometry.minGapFloor)
        // and the kept rings really are the 0.85 ones
        #expect(m.rings == (0..<7).map { ContourInkGeometry.ring($0, of: 7, seed: seed, wobble: 0.85) })
    }

    @Test func theScalesAreTriedFromFullDownToPlainCircles() {
        #expect(ContourInkGeometry.wobbleScales.first == 1)
        #expect(ContourInkGeometry.wobbleScales.last == 0)
        #expect(zip(ContourInkGeometry.wobbleScales, ContourInkGeometry.wobbleScales.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func plainCirclesAlwaysFitAtEveryCount() {
        for n in 3...12 {
            let rs = (0..<n).map { ContourInkGeometry.ring($0, of: n, seed: 1, wobble: 0) }
            #expect(ContourMap.minGap(of: rs) >= ContourInkGeometry.minGapFloor, "n=\(n)")
        }
    }

    @Test func gapIsNegativeForCrossingRings() {
        let m = ContourMap.make()
        var moved = m.rings[1]
        moved.center = moved.center + Vec2(0.3, 0)
        moved.points = moved.points.map { $0 + Vec2(0.3, 0) }
        #expect(ContourInkGeometry.gap(outer: m.rings[0], inner: moved) < 0)
    }

    @Test func gapIsNegativeWhenTheRingsAreSwapped() {
        let m = ContourMap.make()
        #expect(ContourInkGeometry.gap(outer: m.rings[3], inner: m.rings[2]) < 0)
    }

    @Test func gapIsExactForConcentricCircles() {
        let a = ContourInkGeometry.ring(0, of: 7, seed: 1, wobble: 0)
        var b = ContourInkGeometry.ring(1, of: 7, seed: 1, wobble: 0)
        b.center = .zero
        b.points = (0..<120).map { Vec2.unit(2 * Double.pi * Double($0) / 120) * b.radius }
        var a0 = a
        a0.points = (0..<120).map { Vec2.unit(2 * Double.pi * Double($0) / 120) * a.radius }
        let g = ContourInkGeometry.gap(outer: a0, inner: b)
        let chordSlack = a.radius * (1 - cos(Double.pi / 120))
        #expect(abs(g - (a.radius - b.radius)) < chordSlack + 1e-9)
    }
}

@Suite struct RingQueryTests {
    @Test func pointAtFractionHitsTheSamplePoints() {
        let r = ContourMap.make().rings[3]
        for i in stride(from: 0, to: r.points.count, by: 7) {
            #expect(r.point(at: r.cumulative[i] / r.length).distance(to: r.points[i]) < 1e-9)
        }
    }

    @Test func pointAtZeroAndOneIsTheStartOfTheStroke() {
        for r in ContourMap.make().rings {
            #expect(r.point(at: 0) == r.points[0])
            #expect(r.point(at: 1).distance(to: r.points[0]) < 1e-9)
        }
    }

    @Test func pointAtFractionIsClampedAndSafe() {
        let r = ContourMap.make().rings[0]
        #expect(r.point(at: -2) == r.point(at: 0))
        #expect(r.point(at: 7).distance(to: r.point(at: 1)) < 1e-12)
        #expect(r.point(at: .nan) == r.point(at: 0))
        #expect(r.point(at: .infinity).distance(to: r.point(at: 1)) < 1e-12)
    }

    @Test func pointAtFractionTravelsAtConstantSpeed() {
        let r = ContourMap.make().rings[4]
        let d = 1.0 / 400
        for i in 0..<400 {
            let a = r.point(at: Double(i) * d), b = r.point(at: Double(i + 1) * d)
            #expect(abs(a.distance(to: b) - r.length * d) < r.length * d * 0.02 + 1e-12 || a.distance(to: b) < r.length * d)
        }
    }

    @Test func halfwayAlongTheArcIsHalfwayAroundTheLength() {
        let r = ContourMap.make().rings[1]
        // walk the polyline to half the length and compare
        var walked = 0.0, i = 0
        while walked + r.points[i].distance(to: r.points[(i + 1) % r.points.count]) < r.length / 2 {
            walked += r.points[i].distance(to: r.points[(i + 1) % r.points.count]); i += 1
        }
        let rest = r.length / 2 - walked
        let dir = (r.points[(i + 1) % r.points.count] - r.points[i]).normalized
        #expect(r.point(at: 0.5).distance(to: r.points[i] + dir * rest) < 1e-9)
    }

    @Test func containsAndDistanceBehave() {
        let r = ContourMap.make().rings[0]
        #expect(r.contains(.zero))
        #expect(r.contains(ContourInkGeometry.peak))
        #expect(!r.contains(Vec2(0.49, 0.49)))
        #expect(!r.contains(Vec2(-0.5, 0)))
        #expect(r.distance(to: r.points[10]) < 1e-12)
        #expect(abs(r.distance(to: .zero) - (r.points.map { $0.length }.min() ?? 0)) < 0.005)
        #expect(r.distance(to: Vec2(0.5, 0.5)) > 0.1)
    }

    @Test func theExactCurveAndThePolylineAgreeToWithinASliver() {
        let r = ContourMap.make().rings[0]
        for i in 0..<360 {
            let p = r.point(atAngle: Double(i) * 0.01745)
            #expect(r.distance(to: p) < 0.0008)
        }
    }
}
