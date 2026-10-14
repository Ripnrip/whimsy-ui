import Foundation
import WhimsyCore

/// One tile's animated state.
public struct TileState: Equatable, Sendable {
    public var position: Vec2
    public var rotation: Double
    public var scale: Double
    public var velocity: Vec2 = .zero
    public var angularVelocity = 0.0
    public var scaleVelocity = 0.0
    /// Seconds left before this tile starts moving toward its current target.
    public var delay = 0.0
    /// Fixed per seed: some tiles are snappier, some lazier.
    public let stiffness: Double

    /// How far the tile is from its home slot (0 when home).
    public func liftAmount(home: Vec2) -> Double { position.distance(to: home) }
}

/// Scatter & regroup: tiles fly to random spots (tilted, scaled) and spring back home in a
/// ripple from the centre outward, reporting each tile's landing so the UI can tick a haptic.
/// Deterministic: everything random comes from a `SeededRandom`, and `step(dt)` uses fixed substeps.
public struct ScatterRegroupModel: Equatable, Sendable {
    public static let maxSubstep = 1.0 / 240.0
    public static let maxFrameDelta = 0.1

    public private(set) var layout: TileLayout
    public let tuning: ScatterTuning
    public private(set) var tiles: [TileState]
    public private(set) var targets: [ScatterTarget]
    public private(set) var isScattered = false
    /// Tiles still due to land in the current regroup.
    public private(set) var pendingLandings: Set<Int> = []
    public private(set) var time = 0.0
    private var rng: SeededRandom

    public init(layout: TileLayout, seed: UInt64 = 0x5CA7, tuning: ScatterTuning = ScatterTuning()) {
        self.layout = layout
        self.tuning = tuning
        var rng = SeededRandom(seed: seed)
        tiles = (0..<layout.count).map { i in
            TileState(position: layout.home(i), rotation: 0, scale: 1,
                      stiffness: tuning.baseStiffness * rng.uniform(tuning.stiffnessSpread))
        }
        targets = (0..<layout.count).map { ScatterTarget(position: layout.home($0), rotation: 0, scale: 1) }
        self.rng = rng
    }

    // MARK: Commands

    public mutating func toggle(animated: Bool = true) {
        if isScattered { regroup(animated: animated) } else { scatter(animated: animated) }
    }

    /// Flies every tile to a fresh random target (each scatter is different, but the sequence is fixed per seed).
    public mutating func scatter(animated: Bool = true) {
        isScattered = true
        pendingLandings = []
        for i in tiles.indices {
            targets[i] = layout.scatterTarget(using: &rng, tuning: tuning)
            tiles[i].delay = animated ? rng.uniform(tuning.scatterJitter) : 0
            if !animated { snap(i, to: targets[i]) }
        }
    }

    /// Springs every tile home, starting from the centre and rippling outward.
    public mutating func regroup(animated: Bool = true) {
        isScattered = false
        let delays = layout.rippleDelays(duration: tuning.rippleDuration)
        for i in tiles.indices {
            targets[i] = ScatterTarget(position: layout.home(i), rotation: 0, scale: 1)
            tiles[i].delay = animated ? delays[i] : 0
            if !animated { snap(i, to: targets[i]) }
        }
        // Only tiles that are actually away from home can "land".
        pendingLandings = animated
            ? Set(tiles.indices.filter { tiles[$0].liftAmount(home: layout.home($0)) > tuning.landingRadius })
            : []
    }

    /// Re-lays the grid for a new size. Home targets follow; scatter targets are rescaled.
    public mutating func resize(width: Double, height: Double) {
        let old = layout
        let new = TileLayout(columns: old.columns, rows: old.rows, width: width, height: height, spacing: old.spacing)
        guard new != old else { return }
        layout = new
        let sx = old.width > 0 ? new.width / old.width : 1
        let sy = old.height > 0 ? new.height / old.height : 1
        for i in tiles.indices {
            if isScattered {
                targets[i].position = Vec2(targets[i].position.x * sx, targets[i].position.y * sy)
            } else {
                targets[i] = ScatterTarget(position: new.home(i), rotation: 0, scale: 1)
            }
            snap(i, to: targets[i])
        }
        pendingLandings = []
    }

    private mutating func snap(_ i: Int, to t: ScatterTarget) {
        tiles[i].position = t.position
        tiles[i].rotation = t.rotation
        tiles[i].scale = t.scale
        tiles[i].velocity = .zero
        tiles[i].angularVelocity = 0
        tiles[i].scaleVelocity = 0
        tiles[i].delay = 0
    }

    // MARK: Simulation

    /// Advances the simulation. Returns the indices of tiles that landed during this step, in landing order.
    @discardableResult
    public mutating func step(dt: Double) -> [Int] {
        guard dt.isFinite, dt > 0 else { return [] }
        var landed: [Int] = []
        var remaining = min(dt, Self.maxFrameDelta)
        while remaining > 0 {
            let h = min(remaining, Self.maxSubstep)
            for i in tiles.indices {
                var tile = tiles[i]
                if tile.delay > 0 {
                    tile.delay = max(tile.delay - h, 0)
                    tiles[i] = tile
                    continue
                }
                let target = targets[i]
                let k = tile.stiffness
                let c = 2 * k.squareRoot() * tuning.dampingRatio
                let a = (target.position - tile.position) * k - tile.velocity * c
                tile.velocity += a * h
                tile.position += tile.velocity * h
                tile.angularVelocity += (k * (target.rotation - tile.rotation) - c * tile.angularVelocity) * h
                tile.rotation += tile.angularVelocity * h
                tile.scaleVelocity += (k * (target.scale - tile.scale) - c * tile.scaleVelocity) * h
                tile.scale += tile.scaleVelocity * h
                tiles[i] = tile
                if pendingLandings.contains(i) && tile.position.distance(to: target.position) <= tuning.landingRadius {
                    pendingLandings.remove(i)
                    landed.append(i)
                }
            }
            time += h
            remaining -= h
        }
        return landed
    }

    public var isSettled: Bool {
        tiles.indices.allSatisfy { i in
            let t = tiles[i], g = targets[i]
            return t.delay == 0 && t.position.distance(to: g.position) < 0.05 && t.velocity.length < 0.5
                && abs(t.rotation - g.rotation) < 1e-3 && abs(t.scale - g.scale) < 1e-3
        }
    }
}

/// Rate limiter for landing haptics: a ripple can land many tiles within a few milliseconds,
/// and the Taptic Engine can't render them all distinctly.
public struct LandingThrottle: Equatable, Sendable {
    public var minimumInterval: Double
    public private(set) var lastFire: Double?
    public private(set) var fired = 0

    public init(minimumInterval: Double = 0.05) { self.minimumInterval = minimumInterval }

    /// Call with the time of a landing (any landings at once count as one). Returns whether to fire.
    public mutating func shouldFire(at time: Double) -> Bool {
        if let lastFire, time - lastFire < minimumInterval { return false }
        lastFire = time
        fired += 1
        return true
    }
}
