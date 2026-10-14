/// Pure-Swift model for a bubble-wrap / pop-it grid. No UI framework dependencies,
/// so it is fully unit-testable on any platform (including Linux).

/// A minimal 2D point so the core stays free of CoreGraphics/SwiftUI.
public struct GridPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A minimal 2D size.
public struct GridSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

/// A rectangle in the grid's coordinate space.
public struct GridRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// Source of randomness for feedback intensity; injectable for deterministic tests.
public protocol PopRandomSource {
    /// Returns a value uniformly distributed in `range`.
    mutating func next(in range: ClosedRange<Double>) -> Double
}

/// Default random source backed by the system generator.
public struct SystemPopRandom: PopRandomSource {
    public init() {}
    public mutating func next(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range)
    }
}

/// Deterministic SplitMix64-based random source (handy for tests and previews).
public struct SeededPopRandom: PopRandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53) // [0, 1)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// The grid model. Cells are indexed row-major: `index = row * columns + column`.
public struct PopGrid: Equatable, Sendable {
    public static let defaultColumns = 6
    public static let defaultRows = 8
    /// Range used for randomized haptic intensity.
    public static let intensityRange: ClosedRange<Double> = 0.45...1.0

    public let columns: Int
    public let rows: Int
    public private(set) var popped: Set<Int> = []

    public init(columns: Int = PopGrid.defaultColumns, rows: Int = PopGrid.defaultRows) {
        precondition(columns > 0 && rows > 0, "Grid must have at least one cell")
        self.columns = columns
        self.rows = rows
    }

    public var cellCount: Int { columns * rows }
    public var allPopped: Bool { popped.count == cellCount }
    public var remaining: Int { cellCount - popped.count }

    public func isPopped(_ index: Int) -> Bool { popped.contains(index) }

    public func index(column: Int, row: Int) -> Int? {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return row * columns + column
    }

    public func position(of index: Int) -> (column: Int, row: Int)? {
        guard (0..<cellCount).contains(index) else { return nil }
        return (index % columns, index / columns)
    }

    // MARK: Geometry

    /// Frame of a cell when the grid fills `size`.
    public func cellRect(for index: Int, in size: GridSize) -> GridRect? {
        guard let (c, r) = position(of: index) else { return nil }
        let w = size.width / Double(columns)
        let h = size.height / Double(rows)
        return GridRect(x: Double(c) * w, y: Double(r) * h, width: w, height: h)
    }

    /// Hit-tests `point` against a grid filling `size`. Returns `nil` outside the grid.
    /// The trailing/bottom edges are treated as belonging to the last cell.
    public func cellIndex(at point: GridPoint, in size: GridSize) -> Int? {
        guard size.width > 0, size.height > 0,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0,
              point.x <= size.width, point.y <= size.height else { return nil }
        let column = min(Int(point.x / size.width * Double(columns)), columns - 1)
        let row = min(Int(point.y / size.height * Double(rows)), rows - 1)
        return index(column: column, row: row)
    }

    /// All cells crossed by the segment `from -> to`, in traversal order, without duplicates.
    /// Samples the segment at a sub-cell step so fast drags never skip cells.
    public func cellsCrossed(from start: GridPoint, to end: GridPoint, in size: GridSize) -> [Int] {
        guard size.width > 0, size.height > 0 else { return [] }
        let cellW = size.width / Double(columns)
        let cellH = size.height / Double(rows)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = (dx * dx + dy * dy).squareRoot()
        // Step at most a quarter of the smallest cell dimension.
        let step = max(min(cellW, cellH) / 4, 0.5)
        let samples = max(Int((distance / step).rounded(.up)), 1)

        var result: [Int] = []
        var seen: Set<Int> = []
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let p = GridPoint(x: start.x + dx * t, y: start.y + dy * t)
            if let idx = cellIndex(at: p, in: size), seen.insert(idx).inserted {
                result.append(idx)
            }
        }
        return result
    }

    // MARK: Mutation

    /// Pops a single cell. Returns `true` if it was newly popped.
    @discardableResult
    public mutating func pop(_ index: Int) -> Bool {
        guard (0..<cellCount).contains(index) else { return false }
        return popped.insert(index).inserted
    }

    /// Pops the cell under `point`. Returns the index if it was newly popped.
    @discardableResult
    public mutating func pop(at point: GridPoint, in size: GridSize) -> Int? {
        guard let idx = cellIndex(at: point, in: size), pop(idx) else { return nil }
        return idx
    }

    /// Pops every cell crossed by a drag segment. Returns newly popped indices in order.
    @discardableResult
    public mutating func popDrag(from start: GridPoint?, to end: GridPoint, in size: GridSize) -> [Int] {
        let cells = start.map { cellsCrossed(from: $0, to: end, in: size) }
            ?? cellIndex(at: end, in: size).map { [$0] } ?? []
        return cells.filter { pop($0) }
    }

    public mutating func reset() { popped.removeAll() }

    // MARK: Feedback

    /// Randomized haptic intensity in `intensityRange`.
    public static func feedbackIntensity<R: PopRandomSource>(using rng: inout R) -> Double {
        rng.next(in: intensityRange)
    }

    public static func feedbackIntensity() -> Double {
        var rng = SystemPopRandom()
        return feedbackIntensity(using: &rng)
    }
}

/// Tracks a drag gesture and pops cells along its path, interpolating between samples.
public struct DragPopTracker: Sendable {
    public private(set) var lastPoint: GridPoint?
    public init() {}

    /// Feed each drag sample; returns newly popped cells.
    public mutating func update(_ point: GridPoint, grid: inout PopGrid, size: GridSize) -> [Int] {
        defer { lastPoint = point }
        return grid.popDrag(from: lastPoint, to: point, in: size)
    }

    public mutating func end() { lastPoint = nil }
}
