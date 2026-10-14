import Testing
@testable import PopTherapyCore

@Suite("PopGrid")
struct PopGridTests {
    let size = GridSize(width: 300, height: 400) // 50x50 cells for 6x8

    @Test func defaultDimensions() {
        let grid = PopGrid()
        #expect(grid.columns == 6)
        #expect(grid.rows == 8)
        #expect(grid.cellCount == 48)
        #expect(grid.popped.isEmpty)
        #expect(!grid.allPopped)
    }

    @Test(arguments: [
        (GridPoint(x: 0, y: 0), 0),
        (GridPoint(x: 49.9, y: 49.9), 0),
        (GridPoint(x: 50, y: 0), 1),
        (GridPoint(x: 299, y: 0), 5),
        (GridPoint(x: 0, y: 50), 6),
        (GridPoint(x: 175, y: 225), 4 * 6 + 3),
        (GridPoint(x: 300, y: 400), 47), // bottom-right edge clamps to last cell
    ])
    func hitTesting(point: GridPoint, expected: Int) {
        #expect(PopGrid().cellIndex(at: point, in: size) == expected)
    }

    @Test(arguments: [
        GridPoint(x: -1, y: 10), GridPoint(x: 10, y: -0.1),
        GridPoint(x: 300.1, y: 10), GridPoint(x: 10, y: 401),
        GridPoint(x: .nan, y: 10),
    ])
    func hitTestingOutside(point: GridPoint) {
        #expect(PopGrid().cellIndex(at: point, in: size) == nil)
    }

    @Test func hitTestingZeroSize() {
        #expect(PopGrid().cellIndex(at: GridPoint(x: 0, y: 0), in: GridSize(width: 0, height: 0)) == nil)
    }

    @Test func cellRectRoundTrip() throws {
        let grid = PopGrid()
        for i in 0..<grid.cellCount {
            let r = try #require(grid.cellRect(for: i, in: size))
            #expect(grid.cellIndex(at: GridPoint(x: r.midX, y: r.midY), in: size) == i)
        }
        #expect(grid.cellRect(for: 48, in: size) == nil)
    }

    @Test func popIsIdempotent() {
        var grid = PopGrid()
        let first = grid.pop(3)
        let again = grid.pop(3)
        let negative = grid.pop(-1)
        let tooBig = grid.pop(48)
        #expect(first)
        #expect(!again)
        #expect(!negative)
        #expect(!tooBig)
        #expect(grid.popped == [3])
        #expect(grid.remaining == 47)
    }

    @Test func popAtPoint() {
        var grid = PopGrid()
        let first = grid.pop(at: GridPoint(x: 60, y: 10), in: size)
        let again = grid.pop(at: GridPoint(x: 60, y: 10), in: size)
        let outside = grid.pop(at: GridPoint(x: -5, y: 10), in: size)
        #expect(first == 1)
        #expect(again == nil)
        #expect(outside == nil)
    }

    @Test func fastHorizontalDragDoesNotSkip() {
        var grid = PopGrid()
        // One giant jump across the whole first row.
        let popped = grid.popDrag(from: GridPoint(x: 1, y: 25), to: GridPoint(x: 299, y: 25), in: size)
        #expect(popped == [0, 1, 2, 3, 4, 5])
    }

    @Test func fastDiagonalDragCoversPath() {
        var grid = PopGrid()
        let popped = grid.popDrag(from: GridPoint(x: 1, y: 1), to: GridPoint(x: 299, y: 399), in: size)
        #expect(popped.first == 0)
        #expect(popped.last == 47)
        // Consecutive cells along the path must be 4- or 8-neighbours (no gaps).
        for (a, b) in zip(popped, popped.dropFirst()) {
            let pa = grid.position(of: a)!, pb = grid.position(of: b)!
            #expect(abs(pa.column - pb.column) <= 1 && abs(pa.row - pb.row) <= 1)
        }
    }

    @Test func dragWithoutStartPopsSingleCell() {
        var grid = PopGrid()
        let popped = grid.popDrag(from: nil, to: GridPoint(x: 120, y: 120), in: size)
        #expect(popped == [14])
    }

    @Test func dragOnlyReturnsNewlyPopped() {
        var grid = PopGrid()
        grid.pop(1)
        let popped = grid.popDrag(from: GridPoint(x: 1, y: 25), to: GridPoint(x: 149, y: 25), in: size)
        #expect(popped == [0, 2])
    }

    @Test func dragLeavingGridIgnoresOutside() {
        var grid = PopGrid()
        let popped = grid.popDrag(from: GridPoint(x: 275, y: 25), to: GridPoint(x: 500, y: 25), in: size)
        #expect(popped == [5])
    }

    @Test func trackerInterpolatesAcrossSamples() {
        var grid = PopGrid()
        var tracker = DragPopTracker()
        let tap = tracker.update(GridPoint(x: 25, y: 25), grid: &grid, size: size)
        #expect(tap == [0])
        // One huge jump straight down the first column.
        let jump = tracker.update(GridPoint(x: 25, y: 375), grid: &grid, size: size)
        #expect(jump == [6, 12, 18, 24, 30, 36, 42])
        tracker.end()
        #expect(tracker.lastPoint == nil)
        // A new drag must not connect to the previous one.
        let next = tracker.update(GridPoint(x: 275, y: 375), grid: &grid, size: size)
        #expect(next == [47])
    }

    @Test func allPoppedAndReset() {
        var grid = PopGrid()
        for i in 0..<grid.cellCount { grid.pop(i) }
        #expect(grid.allPopped)
        #expect(grid.remaining == 0)
        grid.reset()
        #expect(grid.popped.isEmpty)
        #expect(!grid.allPopped)
    }

    @Test func sweepEveryRowPopsAll() {
        var grid = PopGrid()
        var tracker = DragPopTracker()
        for row in 0..<8 {
            let y = Double(row) * 50 + 25
            _ = tracker.update(GridPoint(x: 0, y: y), grid: &grid, size: size)
            _ = tracker.update(GridPoint(x: 300, y: y), grid: &grid, size: size)
            tracker.end()
        }
        #expect(grid.allPopped)
    }

    @Test func customDimensions() {
        let grid = PopGrid(columns: 3, rows: 2)
        #expect(grid.cellCount == 6)
        #expect(grid.cellIndex(at: GridPoint(x: 99, y: 99), in: GridSize(width: 100, height: 100)) == 5)
    }

    @Test func feedbackIntensityInRange() {
        for _ in 0..<500 {
            #expect(PopGrid.intensityRange.contains(PopGrid.feedbackIntensity()))
        }
    }

    @Test func feedbackIntensityIsRandomized() {
        var rng = SeededPopRandom(seed: 42)
        let values = (0..<50).map { _ in PopGrid.feedbackIntensity(using: &rng) }
        #expect(values.allSatisfy { PopGrid.intensityRange.contains($0) })
        #expect(Set(values).count > 40)
    }

    @Test func seededRandomIsDeterministic() {
        var a = SeededPopRandom(seed: 7), b = SeededPopRandom(seed: 7)
        for _ in 0..<20 {
            let x = PopGrid.feedbackIntensity(using: &a)
            let y = PopGrid.feedbackIntensity(using: &b)
            #expect(x == y)
        }
    }
}
