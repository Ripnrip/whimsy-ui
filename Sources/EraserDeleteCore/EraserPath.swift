import Foundation
import WhimsyCore

/// Where the eraser is, which way it's heading and how it's tilted.
public struct EraserPose: Equatable, Sendable {
    public var position: Vec2
    /// Unit tangent of the motion.
    public var direction: Vec2
    /// Tilt in radians (positive = clockwise on screen). The top of the eraser trails behind
    /// horizontal motion and stands upright at turn-arounds.
    public var rotation: Double
    public init(position: Vec2, direction: Vec2, rotation: Double) {
        self.position = position
        self.direction = direction
        self.rotation = rotation
    }
}

/// A back-and-forth zig-zag sweep across a card: horizontal passes joined by half-circle
/// turn-arounds just outside the card edges.
///
/// Coverage is complete by construction. Each pass erases a band `eraserWidth` tall, the
/// bands are spaced at most `eraserWidth * (1 - overlap)` apart, and the first and last
/// passes sit within half an eraser of the top and bottom edges. Each pass also spans the
/// full card width.
public struct EraserPath: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        case line(from: Vec2, to: Vec2)
        /// Arc around `center`, from `startAngle`, sweeping `sweep` radians (y-down space).
        case arc(center: Vec2, radius: Double, startAngle: Double, sweep: Double)

        public var length: Double {
            switch self {
            case let .line(a, b): a.distance(to: b)
            case let .arc(_, r, _, sweep): abs(sweep) * r
            }
        }

        func point(at t: Double) -> Vec2 {
            switch self {
            case let .line(a, b):
                return Vec2.lerp(a, b, t)
            case let .arc(c, r, start, sweep):
                let angle = start + sweep * t
                return c + Vec2(cos(angle), sin(angle)) * r
            }
        }

        func direction(at t: Double) -> Vec2 {
            switch self {
            case let .line(a, b):
                return (b - a).normalized
            case let .arc(_, _, start, sweep):
                let angle = start + sweep * t
                let sign: Double = sweep >= 0 ? 1 : -1
                return Vec2(-sin(angle), cos(angle)) * sign
            }
        }
    }

    public let cardSize: CardSize
    public let eraserWidth: Double
    public let overlap: Double
    /// Maximum tilt (radians) while moving horizontally.
    public let maxTilt: Double
    /// Vertical centres of each horizontal pass.
    public let rowCenters: [Double]
    public let segments: [Segment]
    public let length: Double
    /// Progress values (0...1) of each turn-around apex (where horizontal motion reverses).
    public let turnProgresses: [Double]
    private let cumulative: [Double]

    /// - Parameters:
    ///   - cardSize: the card to wipe.
    ///   - eraserWidth: diameter of the erased stroke (points).
    ///   - overlap: fraction (0..<1) of the eraser width that adjacent passes overlap.
    ///   - leadIn: how far before the card's left edge the eraser starts, in eraser widths.
    public init(cardSize: CardSize, eraserWidth: Double, overlap: Double = 0.25,
                leadIn: Double = 0.75, maxTilt: Double = 0.32) {
        precondition(eraserWidth > 0, "Eraser width must be positive")
        let overlap = min(max(overlap, 0), 0.9)
        self.cardSize = cardSize
        self.eraserWidth = eraserWidth
        self.overlap = overlap
        self.maxTilt = maxTilt

        let w = max(cardSize.width, 0), h = max(cardSize.height, 0)
        let half = eraserWidth / 2
        // Top/bottom passes sit slightly inside half an eraser so the edges are definitely wiped.
        let edgeInset = half * (1 - overlap / 2)
        let maxSpacing = eraserWidth * (1 - overlap)

        var rows: [Double]
        if h <= 2 * edgeInset {
            rows = [h / 2]
        } else {
            let first = edgeInset, last = h - edgeInset
            let count = Int(((last - first) / maxSpacing).rounded(.up)) + 1
            let spacing = (last - first) / Double(count - 1)
            rows = (0..<count).map { first + Double($0) * spacing }
        }
        rowCenters = rows

        var segments: [Segment] = []
        var turns: [Int] = [] // index of each turn arc in `segments`
        let lead = leadIn * eraserWidth
        for (i, y) in rows.enumerated() {
            let goingRight = i.isMultiple(of: 2)
            let isFirst = i == 0, isLast = i == rows.count - 1
            var start = goingRight ? 0.0 : w
            var end = goingRight ? w : 0.0
            if isFirst { start = goingRight ? -lead : w + lead }
            if isLast { end = goingRight ? w + lead : -lead }
            segments.append(.line(from: Vec2(start, y), to: Vec2(end, y)))
            if !isLast {
                let nextY = rows[i + 1]
                let radius = (nextY - y) / 2
                let center = Vec2(end, y + radius)
                // Right side: top → rightmost → bottom (clockwise, +π). Left side: top → leftmost → bottom (−π).
                turns.append(segments.count)
                segments.append(.arc(center: center, radius: radius, startAngle: -.pi / 2,
                                     sweep: goingRight ? .pi : -.pi))
            }
        }
        self.segments = segments

        var cumulative: [Double] = [0]
        for s in segments { cumulative.append(cumulative.last! + s.length) }
        self.cumulative = cumulative
        let total = cumulative.last!
        length = total
        turnProgresses = total > 0 ? turns.map { (cumulative[$0] + segments[$0].length / 2) / total } : []
    }

    public var turnCount: Int { turnProgresses.count }

    /// Locates `progress` (clamped to 0...1) as (segment index, local t).
    private func locate(_ progress: Double) -> (Int, Double) {
        guard length > 0, !segments.isEmpty else { return (0, 0) }
        let p = progress.isFinite ? min(max(progress, 0), 1) : 0
        let s = p * length
        // Binary search the cumulative arc lengths.
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid + 1] < s { lo = mid + 1 } else { hi = mid }
        }
        let segLength = segments[lo].length
        let t = segLength > 0 ? (s - cumulative[lo]) / segLength : 0
        return (lo, min(max(t, 0), 1))
    }

    public func point(at progress: Double) -> Vec2 {
        guard !segments.isEmpty else { return .zero }
        let (i, t) = locate(progress)
        return segments[i].point(at: t)
    }

    public func direction(at progress: Double) -> Vec2 {
        guard !segments.isEmpty else { return Vec2(1, 0) }
        let (i, t) = locate(progress)
        return segments[i].direction(at: t)
    }

    /// Position + rotation for `progress` in 0...1.
    public func pose(at progress: Double) -> EraserPose {
        let direction = direction(at: progress)
        return EraserPose(position: point(at: progress), direction: direction,
                          rotation: Self.tilt(for: direction, maxTilt: maxTilt))
    }

    /// Tilt for a motion direction: the top trails behind horizontal motion.
    public static func tilt(for direction: Vec2, maxTilt: Double) -> Double {
        -maxTilt * min(max(direction.normalized.x, -1), 1)
    }

    /// Number of turn-around apexes passed when progress moves from `from` to `to` (forward only).
    public func turnsCrossed(from: Double, to: Double) -> Int {
        guard to > from else { return 0 }
        return turnProgresses.reduce(0) { $0 + ($1 > from && $1 <= to ? 1 : 0) }
    }

    /// Points along the path between two progress values, spaced at most `maxStep` apart
    /// (both ends included).
    public func samples(from: Double, to: Double, maxStep: Double) -> [Vec2] {
        let a = min(max(from, 0), 1), b = min(max(to, 0), 1)
        guard b > a, length > 0 else { return [point(at: b)] }
        let count = max(Int(((b - a) * length / max(maxStep, 0.25)).rounded(.up)), 1)
        return (0...count).map { point(at: a + (b - a) * Double($0) / Double(count)) }
    }
}
