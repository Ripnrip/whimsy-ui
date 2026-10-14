import WhimsyCore
/// Detects back-and-forth reversals of horizontal motion during a manual scrub, with
/// hysteresis so jitter doesn't produce ticks.
public struct ReversalDetector: Equatable, Sendable {
    public let threshold: Double
    private var extremeX: Double?
    private var direction: Double = 0

    public init(threshold: Double) { self.threshold = max(threshold, 0) }

    /// Feed the next x; returns `true` when the horizontal direction has reversed.
    public mutating func update(x: Double) -> Bool {
        guard let extreme = extremeX else { extremeX = x; return false }
        let delta = x - extreme
        if direction == 0 {
            if abs(delta) >= threshold { direction = delta > 0 ? 1 : -1; extremeX = x }
            return false
        }
        if delta * direction > 0 { extremeX = x; return false } // still going the same way
        if abs(delta) >= threshold {
            direction = -direction
            extremeX = x
            return true
        }
        return false
    }

    public mutating func reset() { extremeX = nil; direction = 0 }
}

/// One erase of one card: drives the eraser automatically along an `EraserPath`, or by
/// hand (scrubbing). Either way it records the strokes for the mask and keeps a coverage
/// estimate.
public struct EraserSession: Equatable, Sendable {
    public static let defaultFullyWipedThreshold = 0.96

    public let path: EraserPath
    public let fullyWipedThreshold: Double
    public private(set) var coverage: CoverageGrid
    /// Polylines of the eraser centre; draw with line width `eraserWidth`, round caps and joins.
    public private(set) var strokes: [[Vec2]] = []
    /// Auto-erase progress, 0...1.
    public private(set) var progress: Double = 0
    /// Total turn-arounds so far (auto turns + manual reversals); a haptic trigger.
    public private(set) var turnCount = 0
    public private(set) var pose: EraserPose?
    public private(set) var isScrubbing = false
    private var reversal: ReversalDetector

    public var eraserWidth: Double { path.eraserWidth }
    public var eraserRadius: Double { path.eraserWidth / 2 }
    public var cardSize: CardSize { path.cardSize }
    public var coveredFraction: Double { coverage.fraction }
    public var isFullyWiped: Bool { coverage.fraction >= fullyWipedThreshold }

    public init(cardSize: CardSize, eraserWidth: Double, overlap: Double = 0.25,
                fullyWipedThreshold: Double = EraserSession.defaultFullyWipedThreshold,
                coverageCellSize: Double = 4) {
        path = EraserPath(cardSize: cardSize, eraserWidth: eraserWidth, overlap: overlap)
        self.fullyWipedThreshold = fullyWipedThreshold
        coverage = CoverageGrid(cardSize: cardSize, cellSize: coverageCellSize)
        reversal = ReversalDetector(threshold: eraserWidth * 0.5)
    }

    /// Result of moving the eraser.
    public struct Movement: Equatable, Sendable {
        /// Distance travelled, in points (drives crumb emission).
        public var distance: Double = 0
        /// Turn-arounds in this movement (drives haptics).
        public var turns: Int = 0
    }

    // MARK: Automatic

    /// Moves the auto eraser forward to `newProgress` (0...1). Going backwards is ignored.
    @discardableResult
    public mutating func advance(to newProgress: Double) -> Movement {
        let target = newProgress.isFinite ? min(max(newProgress, 0), 1) : progress
        if strokes.isEmpty || pose == nil {
            strokes.append([path.point(at: progress)])
            stampLast()
        }
        guard target > progress else {
            pose = path.pose(at: progress)
            return Movement()
        }
        let points = path.samples(from: progress, to: target, maxStep: eraserRadius * 0.5)
        var movement = Movement()
        for point in points.dropFirst() {
            movement.distance += append(point)
        }
        movement.turns = path.turnsCrossed(from: progress, to: target)
        turnCount += movement.turns
        progress = target
        pose = path.pose(at: progress)
        return movement
    }

    // MARK: Manual scrubbing

    /// Starts a new hand-drawn stroke at `point`.
    public mutating func beginScrub(at point: Vec2) {
        isScrubbing = true
        reversal.reset()
        _ = reversal.update(x: point.x)
        strokes.append([point])
        stampLast()
        pose = EraserPose(position: point, direction: pose?.direction ?? Vec2(1, 0), rotation: pose?.rotation ?? 0)
    }

    /// Continues the hand-drawn stroke to `point`.
    @discardableResult
    public mutating func scrub(to point: Vec2) -> Movement {
        guard isScrubbing, let last = strokes.last?.last else {
            beginScrub(at: point)
            return Movement()
        }
        let delta = point - last
        guard delta.length >= 0.5 else { return Movement() }
        var movement = Movement(distance: append(point))
        if reversal.update(x: point.x) {
            movement.turns = 1
            turnCount += 1
        }
        // Ease the tilt toward the motion so hand jitter doesn't make the eraser twitch.
        let direction = delta.normalized
        let targetTilt = EraserPath.tilt(for: direction, maxTilt: path.maxTilt)
        let previousTilt = pose?.rotation ?? 0
        pose = EraserPose(position: point, direction: direction,
                          rotation: previousTilt + (targetTilt - previousTilt) * 0.35)
        return movement
    }

    public mutating func endScrub() {
        isScrubbing = false
    }

    // MARK: Helpers

    private mutating func append(_ point: Vec2) -> Double {
        guard let last = strokes.last?.last else { return 0 }
        strokes[strokes.count - 1].append(point)
        coverage.stamp(from: last, to: point, radius: eraserRadius)
        return last.distance(to: point)
    }

    private mutating func stampLast() {
        if let p = strokes.last?.last { coverage.stamp(at: p, radius: eraserRadius) }
    }
}
