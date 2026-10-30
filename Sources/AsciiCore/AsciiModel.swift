import Foundation

public struct AsciiTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var duration: Double
    public init(title: String, artist: String, duration: Double) { self.title = title; self.artist = artist; self.duration = duration }

    /// An invented track.
    public static let sample = AsciiTrack(title: "Static Lullaby", artist: "Mira & the Quiet Arcades", duration: 214)
}

/// Play/pause and the scrubber position.
public struct AsciiPlayer: Equatable, Sendable {
    public var duration: Double
    public private(set) var position: Double
    public private(set) var isPlaying: Bool

    public init(duration: Double, position: Double = 0, isPlaying: Bool = true) {
        self.duration = max(duration, 0)
        self.position = WhimsyMath.clamp(position, 0, max(duration, 0))
        self.isPlaying = isPlaying
    }

    public var progress: Double { duration > 0 ? position / duration : 0 }
    public var remaining: Double { max(duration - position, 0) }

    public mutating func toggle() { isPlaying.toggle() }
    public mutating func seek(to p: Double) { position = WhimsyMath.clamp(p, 0, duration) }

    /// Advances while playing. Returns true if the track ended (and playback stopped) during this step.
    @discardableResult
    public mutating func advance(by dt: Double) -> Bool {
        guard isPlaying, dt > 0 else { return false }
        position += dt
        if position >= duration { position = duration; isPlaying = false; return true }
        return false
    }

    /// "m:ss".
    public static func format(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded(.down))
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }
}

public enum AsciiEvent: Equatable, Sendable {
    case scrambleStarted
    /// Every cell is back to its true glyph.
    case resolved
    case haptic
    case playing(Bool)
    case densityChanged(Int)
    case seeked
}

public enum AsciiAnnouncement {
    public static func text(for e: AsciiEvent) -> String? {
        switch e {
        case .playing(let on): return on ? "Playing" : "Paused"
        case .densityChanged(let n): return "Detail \(n) columns, \(AsciiDensity.label(n))"
        default: return nil
        }
    }
}

/// One drawn cell.
public struct AsciiCell: Equatable, Sendable {
    public var glyph: Character
    public var r: Double
    public var g: Double
    public var b: Double
    public var scrambled: Bool
}

/// The card over time: the player, the shimmer, the tap's scramble/resolve, the density and the events.
public struct AsciiModel {
    public struct Config: Equatable, Sendable {
        public var reduceMotion = false
        public var hapticInterval = 0.25
        public var seed: UInt32 = 20261030
        public var shimmer = AsciiShimmer()
        /// Shimmer strength while paused (1 while playing).
        public var pausedEnergy = 0.3
        /// How fast the shimmer strength moves between those, per second.
        public var energyRate = 2.0
        public init() {}
    }

    public var config: Config
    public let track: AsciiTrack
    public private(set) var time = 0.0
    public private(set) var cols: Int
    public private(set) var player: AsciiPlayer
    /// Shimmer strength, 0…1.
    public private(set) var energy = 1.0
    /// Counts taps, so each scramble uses new random glyphs.
    public private(set) var epoch = 0
    public private(set) var scrambleStart: Double?
    public private(set) var scrambleOrigin = Vec2(0.5, 0.5)
    public private(set) var resolveHaptics = 0
    public private(set) var announcementCount = 0
    public private(set) var announcement: String?

    private let source: AsciiImage
    private var grids: [Int: AsciiGrid] = [:]
    private var pending: [AsciiEvent] = []
    private var lastHaptic = -Double.infinity

    public init(track: AsciiTrack = .sample, position: Double = 83, columns: Int = AsciiDensity.defaultColumns, config: Config = Config()) {
        self.track = track
        self.config = config
        player = AsciiPlayer(duration: track.duration, position: position)
        cols = AsciiDensity.clamp(columns)
        source = AsciiCover.image()
        grids[cols] = AsciiGrid(source: source, cols: cols)
    }

    public var isScrambling: Bool { scrambleStart != nil }
    /// Nothing is moving: reduced motion, no scramble, and the scrubber isn't running.
    public var isIdle: Bool { config.reduceMotion && scrambleStart == nil && !player.isPlaying && pending.isEmpty }

    // MARK: Input

    /// Tap the art at `origin` (unit square). Scrambles and resolves back from there; a tap during a
    /// scramble starts over. With Reduce Motion the art stays put and the tap just acknowledges.
    public mutating func tap(at origin: Vec2 = Vec2(0.5, 0.5), time t: Double) {
        step(to: t)
        if config.reduceMotion {
            emit(.resolved)
            haptic()
            return
        }
        epoch += 1
        scrambleStart = time
        scrambleOrigin = Vec2(WhimsyMath.clamp01(origin.x), WhimsyMath.clamp01(origin.y))
        emit(.scrambleStarted)
    }

    public mutating func togglePlay(at t: Double) {
        step(to: t)
        player.toggle()
        emit(.playing(player.isPlaying))
    }

    public mutating func seek(to p: Double, at t: Double) {
        step(to: t)
        player.seek(to: p)
        emit(.seeked)
    }

    /// Sets the density (clamped). Returns whether it changed.
    @discardableResult
    public mutating func setColumns(_ n: Int, at t: Double) -> Bool {
        step(to: t)
        let c = AsciiDensity.clamp(n)
        guard c != cols else { return false }
        cols = c
        if grids[c] == nil { grids[c] = AsciiGrid(source: source, cols: c) }
        emit(.densityChanged(c))
        return true
    }

    /// The accessibility action: one step finer or crunchier.
    @discardableResult
    public mutating func stepDensity(up: Bool, at t: Double) -> Bool { setColumns(AsciiDensity.stepped(cols, up: up), at: t) }

    // MARK: Time

    @discardableResult
    public mutating func advance(to t: Double) -> [AsciiEvent] {
        step(to: t)
        let out = pending
        pending = []
        return out
    }

    private mutating func emit(_ e: AsciiEvent) {
        pending.append(e)
        if case .haptic = e { resolveHaptics += 1 }
        else if let text = AsciiAnnouncement.text(for: e) { announcement = text; announcementCount += 1 }
    }

    private mutating func haptic() {
        if time - lastHaptic >= config.hapticInterval { lastHaptic = time; emit(.haptic) }
    }

    private mutating func step(to t: Double) {
        let t2 = t.isFinite ? max(t, time) : time
        let dt = t2 - time
        if player.advance(by: dt) { emit(.playing(false)) }
        let target = config.reduceMotion ? 0 : (player.isPlaying ? 1 : config.pausedEnergy)
        if config.reduceMotion { energy = 0 }
        else if energy < target { energy = min(target, energy + dt * config.energyRate) }
        else if energy > target { energy = max(target, energy - dt * config.energyRate) }
        time = t2
        if let s = scrambleStart, time - s >= AsciiScramble.total {
            scrambleStart = nil
            emit(.resolved)
            haptic()
        }
    }

    // MARK: Frame

    public var grid: AsciiGrid { grids[cols]! }

    /// Every cell of the current grid, row by row.
    public func cells() -> [AsciiCell] {
        let g = grid, n = g.cols
        let maxD = AsciiScramble.maxDistance(from: scrambleOrigin)
        let elapsed = scrambleStart.map { time - $0 }
        var out: [AsciiCell] = []
        out.reserveCapacity(n * n)
        for row in 0..<n {
            let v = (Double(row) + 0.5) / Double(n)
            for col in 0..<n {
                let u = (Double(col) + 0.5) / Double(n), i = row * n + col
                let sh = config.shimmer.value(u: u, v: v, t: time, energy: energy)
                var tone = g.tones[i] + sh
                var glyph: Character
                var scrambled = false
                if let e = elapsed {
                    let d = min(1, Vec2(u, v).distance(to: scrambleOrigin) / maxD)
                    let h = AsciiHash.unit(AsciiHash.hash(config.seed, UInt32(i), 99))
                    switch AsciiScramble.state(elapsed: e, distance: d, jitter: h) {
                    case .calm: glyph = AsciiRamp.glyph(tone: tone)
                    case .scrambled:
                        scrambled = true
                        glyph = AsciiRamp.extended[AsciiScramble.randomGlyphIndex(seed: config.seed, epoch: epoch, cell: i, elapsed: e)]
                    case .settled(let flash):
                        tone += AsciiScramble.flashGain * flash
                        glyph = AsciiRamp.glyph(tone: tone)
                    }
                } else {
                    glyph = AsciiRamp.glyph(tone: tone)
                }
                let c = AsciiRamp.scaled(g.tints[i], by: 1 + AsciiRamp.shimmerTintGain * sh)
                out.append(AsciiCell(glyph: glyph, r: c.r, g: c.g, b: c.b, scrambled: scrambled))
            }
        }
        return out
    }

    // MARK: Accessibility

    public var accessibilityLabel: String { "\(track.title), \(track.artist)" }
    public var accessibilityValue: String {
        "\(player.isPlaying ? "Playing" : "Paused"), \(AsciiPlayer.format(player.position)) of \(AsciiPlayer.format(player.duration)), ASCII cover at \(cols) columns, \(AsciiDensity.label(cols))"
    }
}
