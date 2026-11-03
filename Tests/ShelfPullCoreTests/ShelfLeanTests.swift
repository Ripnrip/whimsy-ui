import Testing
import Foundation
@testable import ShelfPullCore

@Suite struct ShelfLeanTests {
    let layout = ShelfLayout.make()

    @Test func noRiseMeansNoLean() {
        for b in 0..<7 { #expect(ShelfLean.angles(layout: layout, lifted: b, rise: 0).allSatisfy { $0 == 0 }) }
    }

    @Test func smallRisesStartGently() {
        let h = layout.spines[3].height
        #expect(ShelfLean.progress(rise: 0.05 * h, height: h) == 0)
        #expect(ShelfLean.progress(rise: 0.38 * h, height: h) == 1)
        #expect(ShelfLean.progress(rise: 0.2 * h, height: h) > 0.3 && ShelfLean.progress(rise: 0.2 * h, height: h) < 0.7)
        #expect(ShelfLean.progress(rise: .nan, height: h) == 0)
    }

    @Test(arguments: 0..<7)
    func theLiftedBookDoesNotLean(_ b: Int) {
        #expect(ShelfLean.angles(layout: layout, lifted: b, rise: 90)[b] == 0)
    }

    @Test(arguments: 0..<7)
    func neighboursLeanTowardTheGap(_ b: Int) {
        let a = ShelfLean.angles(layout: layout, lifted: b, rise: 70)
        for i in 0..<7 where i < b { #expect(a[i] > 0) }   // left of the gap: clockwise, top moves right
        for i in 0..<7 where i > b { #expect(a[i] < 0) }
    }

    @Test(arguments: 0..<7)
    func neverMoreThanTwelveDegrees(_ b: Int) {
        for r in stride(from: 0.0, through: 200, by: 5) {
            #expect(ShelfLean.angles(layout: layout, lifted: b, rise: r).allSatisfy { abs($0) <= 12 + 1e-9 })
        }
    }

    @Test(arguments: 0..<7)
    func angleShrinksWithDistance(_ b: Int) {
        for r in stride(from: 5.0, through: 130, by: 5) {
            let a = ShelfLean.angles(layout: layout, lifted: b, rise: r)
            var k = 1
            while b - k - 1 >= 0 { #expect(abs(a[b - k - 1]) <= abs(a[b - k]) + 1e-12); k += 1 }
            k = 1
            while b + k + 1 < 7 { #expect(abs(a[b + k + 1]) <= abs(a[b + k]) + 1e-12); k += 1 }
        }
    }

    @Test func farBooksLeanLessThanHalfOfThePreviousWhenFree() {
        // a tall slot with a short neighbour in a wide shelf: the raw halving rule shows through the caps
        let a = ShelfLean.angles(layout: layout, lifted: 3, rise: 120)
        #expect(abs(a[1]) <= 12 * 0.5 + 1e-9)
        #expect(abs(a[0]) <= 12 * 0.25 + 1e-9)
        #expect(abs(a[5]) <= 12 * 0.5 + 1e-9 && abs(a[6]) <= 12 * 0.25 + 1e-9)
    }

    @Test(arguments: 0..<7)
    func leanGrowsWithTheRise(_ b: Int) {
        var prev = [Double](repeating: 0, count: 7)
        for r in stride(from: 0.0, through: 120, by: 2) {
            let a = ShelfLean.angles(layout: layout, lifted: b, rise: r)
            for i in 0..<7 { #expect(abs(a[i]) >= abs(prev[i]) - 1e-12) }
            prev = a
        }
    }

    @Test(arguments: 0..<7)
    func nearestNeighbourTopStaysInsideTheSlot(_ b: Int) {
        let a = ShelfLean.angles(layout: layout, lifted: b, rise: 120)
        for i in [b - 1, b + 1] where i >= 0 && i < 7 {
            let shift = layout.spines[i].height * sin(abs(a[i]) * .pi / 180)
            #expect(shift <= 0.85 * layout.spines[b].width + 1e-9)
        }
    }

    /// Left edge / right edge of a book leaning `deg` (clockwise positive) about its bottom-right corner, at height `H`.
    static func edgesLeaningRight(x: Double, w: Double, deg: Double, at H: Double) -> (left: Double, right: Double) {
        let t = deg * .pi / 180
        let pivot = x + w
        let right = pivot + H * tan(t)
        let y = (H - w * sin(t)) / cos(t)
        return (pivot - w * cos(t) + y * sin(t), right)
    }

    @Test(arguments: 0..<7)
    func leaningBooksNeverOverlapTheirNeighbours(_ b: Int) {
        for seed in UInt32(1)...25 {
            let l = ShelfLayout.make(seed: seed)
            for r in stride(from: 0.0, through: 140, by: 7) {
                let a = ShelfLean.angles(layout: l, lifted: b, rise: r)
                for i in 1..<l.count where i <= b - 1 {
                    // left of the gap: far = i-1, near = i, both pivot on their bottom-right corner
                    let far = l.spines[i - 1], near = l.spines[i]
                    var H = 10.0
                    while H < min(far.height, near.height) - 6 {
                        let f = Self.edgesLeaningRight(x: far.x, w: far.width, deg: a[i - 1], at: H)
                        let n = Self.edgesLeaningRight(x: near.x, w: near.width, deg: a[i], at: H)
                        #expect(f.right <= n.left + 1e-6)
                        H += 10
                    }
                }
                for i in 0..<(l.count - 1) where i >= b + 1 {
                    // right of the gap: mirror x so it becomes the same problem
                    let far = l.spines[i + 1], near = l.spines[i]
                    let mf = ShelfLayout.width - (far.x + far.width), mn = ShelfLayout.width - (near.x + near.width)
                    var H = 10.0
                    while H < min(far.height, near.height) - 6 {
                        let f = Self.edgesLeaningRight(x: mf, w: far.width, deg: -a[i + 1], at: H)
                        let n = Self.edgesLeaningRight(x: mn, w: near.width, deg: -a[i], at: H)
                        #expect(f.right <= n.left + 1e-6)
                        H += 10
                    }
                }
            }
        }
    }

    @Test func mirrorImageForAMirroredShelf() {
        let a2 = ShelfLean.angles(layout: layout, lifted: 2, rise: 60)
        #expect(a2[1] > 0 && a2[3] < 0)
    }

    @Test func pivotIsTheCornerNearestTheGap() {
        #expect(ShelfLean.pivotsOnTrailingCorner(5))
        #expect(!ShelfLean.pivotsOnTrailingCorner(-5))
        #expect(ShelfLean.pivotsOnTrailingCorner(0))
    }

    @Test func badInputsAreHarmless() {
        #expect(ShelfLean.angles(layout: layout, lifted: -1, rise: 50).allSatisfy { $0 == 0 })
        #expect(ShelfLean.angles(layout: layout, lifted: 7, rise: 50).allSatisfy { $0 == 0 })
        #expect(ShelfLean.angles(layout: layout, lifted: 3, rise: .nan).allSatisfy { $0 == 0 })
        #expect(ShelfLean.angles(layout: layout, lifted: 3, rise: -20).allSatisfy { $0 == 0 })
    }

    @Test func wobbleDiesOutAndHalvesWithDistance() {
        #expect(ShelfLean.wobble(distance: 1, at: 0) == 0)
        #expect(ShelfLean.wobble(distance: 0, at: 0.05) == 0)
        #expect(ShelfLean.wobble(distance: 1, at: .nan) == 0)
        for t in stride(from: 0.01, through: 0.4, by: 0.01) {
            #expect(abs(ShelfLean.wobble(distance: 2, at: t) - ShelfLean.wobble(distance: 1, at: t) / 2) < 1e-12)
            #expect(abs(ShelfLean.wobble(distance: 1, at: t)) <= 1.6 * exp(-t / 0.12) + 1e-12)
        }
        #expect(abs(ShelfLean.wobble(distance: 1, at: 0.4)) < 0.06)
    }

    @Test func wobbleRocksBothWays() {
        let samples = stride(from: 0.01, through: 0.4, by: 0.005).map { ShelfLean.wobble(distance: 1, at: $0) }
        #expect(samples.contains { $0 > 0.2 } && samples.contains { $0 < -0.1 })
    }
}
