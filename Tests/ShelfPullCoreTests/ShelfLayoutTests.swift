import Testing
import Foundation
@testable import ShelfPullCore

@Suite struct ShelfHashTests {
    @Test func matchesLowbias32ReferenceValues() {
        let expected: [UInt32: UInt32] = [0: 0, 1: 1_753_845_952, 2: 3_507_691_905, 12345: 2_435_775_735, 0xFFFF_FFFF: 1_734_902_346]
        for (k, v) in expected { #expect(ShelfHash.hash32(k) == v) }
    }

    @Test func unitIsInHalfOpenRange() {
        for s in 0..<500 {
            let u = ShelfHash.unit(UInt32(s), s * 3)
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func unitIsRoughlyUniform() {
        var buckets = [Int](repeating: 0, count: 10)
        for s in 0..<5000 { buckets[min(9, Int(ShelfHash.unit(0xBEEF, s) * 10))] += 1 }
        for b in buckets { #expect(b > 380 && b < 620) }
    }

    @Test func saltsGiveDifferentValues() {
        #expect(Set((0..<200).map { ShelfHash.value(5, $0) }).count == 200)
    }
}

@Suite struct ShelfLayoutTests {
    @Test func defaultShelfHasSevenBooks() {
        #expect(ShelfLayout.make().count == 7)
    }

    @Test(arguments: [-5, 0, 1, 2, 3, 5, 9, 10, 100])
    func countIsClamped(_ n: Int) {
        let c = ShelfLayout.make(count: n).count
        #expect(c == min(max(n, 3), 9))
    }

    @Test func layoutIsDeterministic() {
        #expect(ShelfLayout.make() == ShelfLayout.make())
        #expect(ShelfLayout.make(seed: 1) != ShelfLayout.make(seed: 2))
    }

    @Test(arguments: [3, 4, 5, 6, 7, 8, 9])
    func spinesStayOnTheShelfInOrderWithoutOverlap(_ n: Int) {
        for seed in UInt32(1)...30 {
            let l = ShelfLayout.make(count: n, seed: seed)
            #expect(l.spines.first!.x >= ShelfLayout.sideMargin - 0.001)
            #expect(l.spines.last!.x + l.spines.last!.width <= ShelfLayout.width - ShelfLayout.sideMargin + 0.001)
            for (a, b) in zip(l.spines, l.spines.dropFirst()) {
                #expect(abs(b.x - (a.x + a.width + ShelfLayout.gap)) < 1e-9)
            }
        }
    }

    @Test func shelfIsCentred() {
        for seed in UInt32(1)...30 {
            let l = ShelfLayout.make(seed: seed)
            let left = l.spines.first!.x, right = ShelfLayout.width - (l.spines.last!.x + l.spines.last!.width)
            #expect(abs(left - right) < 1e-9)
        }
    }

    @Test func sizesVaryAndStayInRange() {
        for seed in UInt32(1)...30 {
            let l = ShelfLayout.make(seed: seed)
            for s in l.spines {
                #expect(s.height >= ShelfLayout.minSpineHeight && s.height <= ShelfLayout.minSpineHeight + ShelfLayout.spineHeightSpread + 10)
                #expect(s.width >= 20 && s.width <= ShelfLayout.minSpineWidth + ShelfLayout.spineWidthSpread)
            }
            #expect(Set(l.spines.map { Int($0.height) }).count >= 4)
            #expect(Set(l.spines.map { Int($0.width) }).count >= 4)
        }
    }

    @Test func neighbouringHeightsDiffer() {
        for seed in UInt32(1)...60 {
            let l = ShelfLayout.make(seed: seed)
            for (a, b) in zip(l.spines, l.spines.dropFirst()) { #expect(abs(a.height - b.height) >= ShelfLayout.minHeightStep - 1e-9) }
        }
    }

    @Test func booksFitUnderTheCardAndAbovePlank() {
        for seed in UInt32(1)...30 {
            for s in ShelfLayout.make(seed: seed).spines {
                #expect(s.restRect.y > 0)
                #expect(s.restRect.maxY == ShelfLayout.plankTop)
            }
        }
    }

    @Test func bandsAreSortedAndInsideTheSpine() {
        for seed in UInt32(1)...30 {
            for s in ShelfLayout.make(seed: seed).spines {
                #expect(s.bands.count >= 3 && s.bands.count <= 4)
                #expect(s.bands == s.bands.sorted())
                #expect(s.bands.allSatisfy { $0 > 0 && $0 < 1 })
            }
        }
    }

    @Test func overfullShelvesShrinkToFit() {
        // a hand-made over-wide request is impossible through make(); simulate the maximum, 9 books
        let l = ShelfLayout.make(count: 9, seed: 3)
        let total = l.spines.map(\.width).reduce(0, +) + ShelfLayout.gap * 8
        #expect(total <= ShelfLayout.width - 2 * ShelfLayout.sideMargin + 0.001)
    }

    @Test func liftedRisePutsTheBookCentreOnTheStage() {
        let l = ShelfLayout.make()
        for s in l.spines {
            let centreY = ShelfLayout.plankTop - s.height / 2 - l.liftedRise(s.index)
            #expect(abs(centreY - ShelfLayout.stage.y) < 1e-9)
            #expect(l.liftedRise(s.index) > 0)
        }
    }

    @Test func liftedRiseClampsTheIndex() {
        let l = ShelfLayout.make()
        #expect(l.liftedRise(-4) == l.liftedRise(0))
        #expect(l.liftedRise(99) == l.liftedRise(6))
    }

    @Test func coverRectIsCentredOnTheStageAndProportional() {
        let l = ShelfLayout.make()
        for s in l.spines {
            let r = l.coverRect(s.index)
            #expect(abs(r.midX - ShelfLayout.stage.x) < 1e-9 && abs(r.midY - ShelfLayout.stage.y) < 1e-9)
            #expect(abs(r.width / r.height - ShelfLayout.coverAspect) < 1e-9)
            #expect(abs(r.height - s.height * ShelfLayout.stageScale) < 1e-9)
            #expect(abs(s.coverWidth - 0.7 * s.height) < 1e-9)
        }
    }

    @Test func cardIsCentredAndFitsAboveThePlank() {
        let c = ShelfLayout.cardRect
        #expect(abs(c.midX - ShelfLayout.stage.x) < 1e-9)
        #expect(c.x >= 0 && c.maxX <= ShelfLayout.width)
        #expect(c.maxY < ShelfLayout.plankTop)
    }

    @Test func everyCoverFitsInsideTheCard() {
        let l = ShelfLayout.make()
        for s in l.spines {
            let r = l.coverRect(s.index)
            #expect(r.width < ShelfLayout.cardRect.width && r.height <= ShelfLayout.cardRect.height)
        }
    }

    @Test func hitTestFindsTheBookUnderThePoint() {
        let l = ShelfLayout.make()
        for s in l.spines {
            #expect(l.spine(atX: s.centerX, y: ShelfLayout.plankTop - 10) == s.index)
            #expect(l.spine(atX: s.centerX, y: ShelfLayout.plankTop - s.height + 1) == s.index)
        }
    }

    @Test func hitTestMissesAboveBelowAndOutside() {
        let l = ShelfLayout.make()
        let s = l.spines[1]
        #expect(l.spine(atX: s.centerX, y: ShelfLayout.plankTop - s.height - 2) == nil)
        #expect(l.spine(atX: s.centerX, y: ShelfLayout.plankTop + 4) == nil)
        #expect(l.spine(atX: 2, y: ShelfLayout.plankTop - 20) == nil)
        #expect(l.spine(atX: ShelfLayout.width - 2, y: ShelfLayout.plankTop - 20) == nil)
        #expect(l.spine(atX: .nan, y: 200) == nil)
        #expect(l.spine(atX: 100, y: .infinity) == nil)
    }

    @Test func shortBookIsNotHitAboveItsTop() {
        let l = ShelfLayout.make()
        let shortest = l.spines.min { $0.height < $1.height }!
        #expect(l.spine(atX: shortest.centerX, y: ShelfLayout.plankTop - 160) == nil || shortest.height >= 160)
    }

    @Test func rectHelpers() {
        let r = ShelfRect(x: 10, y: 20, width: 30, height: 40)
        #expect(r.midX == 25 && r.midY == 40 && r.maxX == 40 && r.maxY == 60)
        #expect(r.contains(10, 20) && r.contains(40, 60) && !r.contains(9.9, 30))
        let m = ShelfRect.lerp(r, ShelfRect(x: 0, y: 0, width: 10, height: 10), 0.5)
        #expect(m == ShelfRect(x: 5, y: 10, width: 20, height: 25))
    }
}
