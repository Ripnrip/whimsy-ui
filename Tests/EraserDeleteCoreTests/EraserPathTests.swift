import Testing
import Foundation
@testable import EraserDeleteCore

@Suite("Zig-zag path")
struct EraserPathTests {
    static let cards: [(CardSize, Double)] = [
        (CardSize(width: 340, height: 80), 32),
        (CardSize(width: 200, height: 200), 40),
        (CardSize(width: 375, height: 120), 28),
        (CardSize(width: 120, height: 33), 24),
        (CardSize(width: 90, height: 20), 30),   // shorter than the eraser: one pass
    ]

    @Test(arguments: cards)
    func rowsSpanTheCardWithOverlap(card: CardSize, width: Double) throws {
        let path = EraserPath(cardSize: card, eraserWidth: width, overlap: 0.25)
        let rows = path.rowCenters
        let first = try #require(rows.first), last = try #require(rows.last)
        #expect(first - width / 2 <= 0)              // top edge inside the first band
        #expect(last + width / 2 >= card.height)     // bottom edge inside the last band
        for (a, b) in zip(rows, rows.dropFirst()) {
            #expect(b - a <= width * 0.75 + 1e-9)    // adjacent bands overlap ≥ 25%
            #expect(b > a)
        }
    }

    @Test func shortCardUsesSinglePass() {
        let path = EraserPath(cardSize: CardSize(width: 90, height: 20), eraserWidth: 30)
        #expect(path.rowCenters == [10])
        #expect(path.turnCount == 0)
        #expect(path.segments.count == 1)
    }

    @Test func startsAndEndsOutsideTheCard() {
        let path = EraserPath(cardSize: CardSize(width: 340, height: 80), eraserWidth: 32)
        #expect(path.point(at: 0).x < 0)
        let end = path.point(at: 1)
        #expect(end.x < 0 || end.x > 340)
    }

    @Test func pathIsContinuous() {
        let path = EraserPath(cardSize: CardSize(width: 340, height: 120), eraserWidth: 30)
        let pts = path.samples(from: 0, to: 1, maxStep: 4)
        for (a, b) in zip(pts, pts.dropFirst()) {
            #expect(a.distance(to: b) <= 4.0 + 1e-6)
        }
    }

    @Test func lengthMatchesSegments() {
        let path = EraserPath(cardSize: CardSize(width: 300, height: 100), eraserWidth: 30)
        let sum = path.segments.reduce(0) { $0 + $1.length }
        #expect(abs(path.length - sum) < 1e-9)
        #expect(path.length > Double(path.rowCenters.count) * 300)
    }

    @Test func turnPointsAreHorizontalReversals() {
        let path = EraserPath(cardSize: CardSize(width: 340, height: 120), eraserWidth: 30)
        #expect(path.turnCount == path.rowCenters.count - 1)
        #expect(path.turnProgresses == path.turnProgresses.sorted())
        for (i, p) in path.turnProgresses.enumerated() {
            #expect(p > 0 && p < 1)
            // At the apex the eraser moves straight down, and it is past the card edge.
            let dir = path.direction(at: p)
            #expect(abs(dir.x) < 1e-6)
            #expect(dir.y > 0.99)
            let x = path.point(at: p).x
            #expect(i.isMultiple(of: 2) ? x > 340 : x < 0)
            // Horizontal direction flips across each turn.
            let before = path.direction(at: p - 0.02).x, after = path.direction(at: p + 0.02).x
            #expect(before * after < 0)
        }
    }

    @Test func turnsCrossedCountsEachApexOnce() {
        let path = EraserPath(cardSize: CardSize(width: 340, height: 120), eraserWidth: 30)
        #expect(path.turnsCrossed(from: 0, to: 1) == path.turnCount)
        let t0 = path.turnProgresses[0]
        #expect(path.turnsCrossed(from: 0, to: t0 - 1e-6) == 0)
        #expect(path.turnsCrossed(from: t0 - 1e-6, to: t0) == 1)
        #expect(path.turnsCrossed(from: t0, to: t0 + 1e-6) == 0)
        #expect(path.turnsCrossed(from: 0.8, to: 0.2) == 0)   // backwards never ticks
        // Stepping in many small frames gives the same total.
        var total = 0
        var last = 0.0
        for i in 1...240 {
            let p = Double(i) / 240
            total += path.turnsCrossed(from: last, to: p)
            last = p
        }
        #expect(total == path.turnCount)
    }

    @Test func rotationLeansWithMotionAndStraightensAtTurns() {
        let path = EraserPath(cardSize: CardSize(width: 340, height: 120), eraserWidth: 30, maxTilt: 0.3)
        let rightward = path.pose(at: 0.05)
        #expect(abs(rightward.direction.x - 1) < 1e-12 && rightward.direction.y == 0)
        #expect(abs(rightward.rotation + 0.3) < 1e-9)
        let apex = path.pose(at: path.turnProgresses[0])
        #expect(abs(apex.rotation) < 1e-6)
        let leftward = path.pose(at: (path.turnProgresses[0] + path.turnProgresses[1]) / 2)
        #expect(abs(leftward.rotation - 0.3) < 1e-9)
    }

    @Test func outOfRangeProgressIsClamped() {
        let path = EraserPath(cardSize: CardSize(width: 200, height: 80), eraserWidth: 30)
        #expect(path.point(at: -1) == path.point(at: 0))
        #expect(path.point(at: 2) == path.point(at: 1))
        #expect(path.point(at: .nan) == path.point(at: 0))
    }

    @Test(arguments: cards)
    func fullSweepCoversEveryCell(card: CardSize, width: Double) {
        let path = EraserPath(cardSize: card, eraserWidth: width)
        var grid = CoverageGrid(cardSize: card, cellSize: 2)
        let pts = path.samples(from: 0, to: 1, maxStep: width / 4)
        for (a, b) in zip(pts, pts.dropFirst()) { grid.stamp(from: a, to: b, radius: width / 2) }
        #expect(grid.fraction == 1)
    }
}

@Suite("Coverage grid")
struct CoverageGridTests {
    @Test func startsEmpty() {
        let grid = CoverageGrid(cardSize: CardSize(width: 100, height: 50), cellSize: 5)
        #expect(grid.columns == 20 && grid.rows == 10)
        #expect(grid.fraction == 0)
    }

    @Test func discStampApproximatesCircleArea() {
        var grid = CoverageGrid(cardSize: CardSize(width: 200, height: 200), cellSize: 1)
        grid.stamp(at: Vec2(100, 100), radius: 20)
        let area = Double(grid.coveredCount)
        #expect(abs(area - Double.pi * 400) / (Double.pi * 400) < 0.03)
    }

    @Test func segmentStampIsACapsule() {
        var grid = CoverageGrid(cardSize: CardSize(width: 200, height: 100), cellSize: 1)
        grid.stamp(from: Vec2(50, 50), to: Vec2(150, 50), radius: 10)
        let expected = 100.0 * 20 + Double.pi * 100
        #expect(abs(Double(grid.coveredCount) - expected) / expected < 0.03)
        #expect(grid.isCovered(column: 100, row: 50))
        #expect(!grid.isCovered(column: 100, row: 70))
    }

    @Test func stampingTwiceDoesNotDoubleCount() {
        var grid = CoverageGrid(cardSize: CardSize(width: 100, height: 100), cellSize: 2)
        let first = grid.stamp(at: Vec2(50, 50), radius: 10)
        let second = grid.stamp(at: Vec2(50, 50), radius: 10)
        #expect(first > 0)
        #expect(second == 0)
    }

    @Test func offCardStampsAreSafe() {
        var grid = CoverageGrid(cardSize: CardSize(width: 100, height: 100), cellSize: 2)
        let added = grid.stamp(from: Vec2(-500, -500), to: Vec2(-300, -400), radius: 10)
        #expect(added == 0)
        grid.stamp(at: Vec2(-5, 50), radius: 10) // overlaps the left edge
        #expect(grid.coveredCount > 0)
    }

    @Test func emptyCardCountsAsWiped() {
        let grid = CoverageGrid(cardSize: CardSize(width: 0, height: 40))
        #expect(grid.fraction == 1)
    }

    @Test func resetClears() {
        var grid = CoverageGrid(cardSize: CardSize(width: 100, height: 100))
        grid.stamp(at: Vec2(50, 50), radius: 30)
        grid.reset()
        #expect(grid.coveredCount == 0 && grid.fraction == 0)
    }
}
