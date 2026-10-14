import WhimsyCore
/// Estimates how much of the card has been wiped by sampling a grid of cell centres.
/// The eraser footprint is a disc of `radius` swept along the stroke (a round-capped,
/// round-joined line), which is exactly what the SwiftUI mask draws.
public struct CoverageGrid: Equatable, Sendable {
    public let cardSize: CardSize
    public let columns: Int
    public let rows: Int
    public private(set) var coveredCount = 0
    private var cells: [Bool]

    /// - Parameter cellSize: sampling resolution in points (smaller = more accurate).
    public init(cardSize: CardSize, cellSize: Double = 4) {
        self.cardSize = cardSize
        let cell = max(cellSize, 0.5)
        columns = cardSize.isEmpty ? 1 : max(Int((cardSize.width / cell).rounded(.up)), 1)
        rows = cardSize.isEmpty ? 1 : max(Int((cardSize.height / cell).rounded(.up)), 1)
        cells = Array(repeating: false, count: columns * rows)
    }

    public var cellCount: Int { cells.count }

    /// Covered fraction, 0...1. An empty card counts as fully covered.
    public var fraction: Double {
        cardSize.isEmpty ? 1 : Double(coveredCount) / Double(cells.count)
    }

    private var cellWidth: Double { cardSize.width / Double(columns) }
    private var cellHeight: Double { cardSize.height / Double(rows) }

    public func center(column: Int, row: Int) -> Vec2 {
        Vec2((Double(column) + 0.5) * cellWidth, (Double(row) + 0.5) * cellHeight)
    }

    public func isCovered(column: Int, row: Int) -> Bool {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return false }
        return cells[row * columns + column]
    }

    /// Marks every cell whose centre is within `radius` of segment `a`–`b`.
    /// Returns the number of newly covered cells.
    @discardableResult
    public mutating func stamp(from a: Vec2, to b: Vec2, radius: Double) -> Int {
        guard !cardSize.isEmpty, radius > 0 else { return 0 }
        let minX = min(a.x, b.x) - radius, maxX = max(a.x, b.x) + radius
        let minY = min(a.y, b.y) - radius, maxY = max(a.y, b.y) + radius
        let c0 = max(Int((minX / cellWidth - 0.5).rounded(.down)), 0)
        let c1 = min(Int((maxX / cellWidth - 0.5).rounded(.up)), columns - 1)
        let r0 = max(Int((minY / cellHeight - 0.5).rounded(.down)), 0)
        let r1 = min(Int((maxY / cellHeight - 0.5).rounded(.up)), rows - 1)
        guard c0 <= c1, r0 <= r1 else { return 0 }
        var added = 0
        for row in r0...r1 {
            for column in c0...c1 where !cells[row * columns + column] {
                if center(column: column, row: row).distance(toSegment: a, b) <= radius {
                    cells[row * columns + column] = true
                    added += 1
                }
            }
        }
        coveredCount += added
        return added
    }

    @discardableResult
    public mutating func stamp(at point: Vec2, radius: Double) -> Int {
        stamp(from: point, to: point, radius: radius)
    }

    public mutating func reset() {
        cells = Array(repeating: false, count: cells.count)
        coveredCount = 0
    }
}
