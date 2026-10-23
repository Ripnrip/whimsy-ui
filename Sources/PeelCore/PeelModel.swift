import Foundation

/// The stickers the card hands out, in order.
public struct StickerDesign: Equatable, Sendable {
    public var emoji: String
    public var name: String
    /// Hue (0…1) of the sticker's tinted face.
    public var hue: Double

    public static let all: [StickerDesign] = [
        StickerDesign(emoji: "🍓", name: "Strawberry", hue: 0.97),
        StickerDesign(emoji: "🌈", name: "Rainbow", hue: 0.55),
        StickerDesign(emoji: "🦄", name: "Unicorn", hue: 0.80),
        StickerDesign(emoji: "⭐️", name: "Star", hue: 0.13),
        StickerDesign(emoji: "🍕", name: "Pizza", hue: 0.07),
        StickerDesign(emoji: "🪐", name: "Planet", hue: 0.66),
    ]
}

/// A piece in the air. `shape` is local to `body.position`. Popped stickers keep their fold
/// (`grab` / `finger`), which relaxes flat as they fly; torn pieces are front face only.
public struct FlyingPiece: Equatable, Sendable {
    public var shape: Polygon
    public var grab: Vec2?
    public var finger: WhimsySpring2D?
    public var body: TumbleBody
    /// Where the sticker's centre (its artwork origin) sits in the piece's local frame.
    public var artOffset = Vec2.zero

    public var peel: PeelState {
        guard let grab, let finger else { return .flat(shape) }
        return PeelState.peel(shape, grab: grab, finger: finger.value)
    }
}

public enum PeelPhase: Equatable, Sendable {
    case idle, peeling, springingBack, popped, torn, respawning
}

public struct PeelModel: Equatable, Sendable {
    public static let size = 180.0
    public static let cornerRadius = 34.0
    /// How close to a corner a touch must start to grab it.
    public static let grabRadius = 44.0
    public static let respawnDuration = 0.6

    public var rules = PeelRules()
    public var physics = TumblePhysics()
    public private(set) var center: Vec2
    public private(set) var phase: PeelPhase = .idle
    public private(set) var designIndex = 0
    public private(set) var grab: Vec2?
    public private(set) var finger: WhimsySpring2D
    public private(set) var pieces: [FlyingPiece] = []
    public private(set) var residueAge: Double?
    public private(set) var respawnAge = PeelModel.respawnDuration
    /// Counters for haptics.
    public private(set) var grabs = 0, pops = 0, tears = 0
    private var fingerOffset = Vec2.zero
    private var tracker = VelocityTracker()
    private var rng: SeededRandom

    public init(center: Vec2, seed: UInt64 = 0x57_1C4E) {
        self.center = center
        finger = WhimsySpring2D(value: center, stiffness: 260, dampingRatio: 0.8)
        rng = SeededRandom(seed: seed)
    }

    public var design: StickerDesign { StickerDesign.all[designIndex % StickerDesign.all.count] }

    public var shape: Polygon {
        Polygon.roundedRect(center: center, width: Self.size, height: Self.size, cornerRadius: Self.cornerRadius)
    }

    /// The four grab points: the middle of each rounded corner (TR, BR, BL, TL).
    public var corners: [Vec2] {
        let k = Self.size / 2 - Self.cornerRadius * (1 - 0.5.squareRoot())
        return [Vec2(k, -k), Vec2(k, k), Vec2(-k, k), Vec2(-k, -k)].map { center + $0 }
    }

    /// The sticker on the card this frame (nil while it's gone).
    public var peel: PeelState? {
        switch phase {
        case .idle, .respawning: return .flat(shape)
        case .peeling, .springingBack:
            guard let grab else { return .flat(shape) }
            return PeelState.peel(shape, grab: grab, finger: finger.value)
        case .popped, .torn: return nil
        }
    }

    /// 0…1 (springy) scale of a fresh sticker landing.
    public var appear: Double {
        phase == .respawning ? LandingSpring.progress(respawnAge, duration: 0.45, bounce: 0.3) : 1
    }

    /// Faint glue left behind by a tear.
    public var residueOpacity: Double {
        guard let a = residueAge else { return 0 }
        return 0.3 * (1 - WhimsyMath.smoothstep(0.5, 1.8, a))
    }

    public var isSettled: Bool { phase == .idle }

    /// Moves the sticker (e.g. on layout). Only while nothing is happening.
    public mutating func setCenter(_ c: Vec2) {
        guard phase == .idle || phase == .respawning, c != center else { return }
        center = c
        finger.snap(to: c)
    }

    // MARK: Gestures

    /// Starts a peel if `point` is near a corner. Returns whether it grabbed.
    @discardableResult
    public mutating func begin(at point: Vec2, time: Double) -> Bool {
        guard phase == .idle || phase == .springingBack else { return false }
        guard let corner = corners.min(by: { $0.distance(to: point) < $1.distance(to: point) }),
              corner.distance(to: point) <= Self.grabRadius else { return false }
        if phase == .springingBack, let g = grab, g != corner { return false }
        grab = corner
        fingerOffset = phase == .springingBack ? point - finger.value : point - corner
        if phase == .idle { finger.snap(to: corner) }
        tracker.reset()
        tracker.add(point, at: time)
        phase = .peeling
        grabs += 1
        return true
    }

    public mutating func move(to point: Vec2, time: Double) {
        guard phase == .peeling else { return }
        tracker.add(point, at: time)
        finger.snap(to: point - fingerOffset)
        guard let p = peel, let fold = p.fold else { return }
        if rules.shouldTear(fraction: p.fraction, velocity: tracker.velocity(at: time), peelDirection: fold.normal) {
            tear(p, release: tracker.velocity(at: time))
        }
    }

    public mutating func end(time: Double) {
        guard phase == .peeling, let p = peel else { return }
        let v = tracker.velocity(at: time)
        switch rules.decide(fraction: p.fraction, velocity: v, peelDirection: p.fold?.normal) {
        case .tear: tear(p, release: v)
        case .popOff: pop(release: v)
        case .springBack:
            finger.x.velocity = v.x; finger.y.velocity = v.y
            phase = .springingBack
        }
    }

    /// Accessibility: peel it off in one go.
    public mutating func popNow() {
        guard phase == .idle else { return }
        grab = corners[0]
        finger.snap(to: Vec2.lerp(corners[0], corners[2], 0.6))
        pop(release: .zero)
    }

    // MARK: Outcomes

    private mutating func pop(release: Vec2) {
        guard let grab else { return }
        let dir = (finger.value - grab)
        var body = physics.launch(at: center, direction: dir, release: release, rng: &rng)
        body.age = 0
        var relax = WhimsySpring2D(value: finger.value - center, stiffness: 120, dampingRatio: 0.9)
        relax.x.velocity = 0; relax.y.velocity = 0
        pieces = [FlyingPiece(shape: shape.translated(by: -center), grab: grab - center, finger: relax, body: body)]
        phase = .popped
        pops += 1
    }

    private mutating func tear(_ p: PeelState, release: Vec2) {
        guard let fold = p.fold, let split = TearGeometry.pieces(of: shape, fold: fold, seed: rng.next()) else {
            pop(release: release); return
        }
        let lc = split.lifted.centroid, sc = split.stuck.centroid
        var lifted = physics.launch(at: lc, direction: fold.normal, release: release, rng: &rng)
        var stuck = physics.launch(at: sc, direction: -fold.normal * 0.4 + Vec2(0, 0.6), release: .zero, rng: &rng)
        if !physics.reduceMotion {
            lifted.spin *= 1.4
            stuck.velocity = stuck.velocity * 0.45
            stuck.spin = -lifted.spin * 0.35
            stuck.age = -0.18          // the stuck half lets go a beat later
        }
        pieces = [FlyingPiece(shape: split.lifted.translated(by: -lc), grab: nil, finger: nil, body: lifted, artOffset: center - lc),
                  FlyingPiece(shape: split.stuck.translated(by: -sc), grab: nil, finger: nil, body: stuck, artOffset: center - sc)]
        residueAge = 0
        phase = .torn
        tears += 1
    }

    // MARK: Time

    public mutating func step(_ dt: Double) {
        let dt = min(max(dt, 0), WhimsySpring.maxFrame)
        switch phase {
        case .idle, .peeling:
            break
        case .springingBack:
            guard let grab else { phase = .idle; return }
            finger.step(toward: grab, dt: dt)
            if finger.isSettled(at: grab, tolerance: 0.25) { finger.snap(to: grab); phase = .idle; self.grab = nil }
        case .popped, .torn:
            for i in pieces.indices {
                if pieces[i].body.age < 0 {
                    // Not yet released: count down in place.
                    pieces[i].body.age = min(pieces[i].body.age + dt, 0)
                } else {
                    physics.step(&pieces[i].body, dt: dt)
                }
                if let g = pieces[i].grab { pieces[i].finger?.step(toward: g, dt: dt) }
            }
            if let a = residueAge { residueAge = a + dt }
            let piecesDone = pieces.allSatisfy { physics.isFinished($0.body) }
            let residueDone = residueAge.map { $0 >= 1.8 } ?? true
            if piecesDone && residueDone {
                pieces = []; residueAge = nil; grab = nil
                designIndex += 1
                respawnAge = 0
                finger.snap(to: center)
                phase = .respawning
            }
        case .respawning:
            respawnAge += dt
            if respawnAge >= Self.respawnDuration { respawnAge = Self.respawnDuration; phase = .idle }
        }
    }

    public func opacity(of piece: FlyingPiece) -> Double { piece.body.age < 0 ? 1 : physics.opacity(piece.body) }
    public func scale(of piece: FlyingPiece) -> Double { piece.body.age < 0 ? 1 : physics.scale(piece.body) }
}

/// SwiftUI's `.spring(duration:bounce:)` step response.
public enum LandingSpring {
    public static func progress(_ t: Double, duration: Double, bounce: Double) -> Double {
        WhimsySpring.stepResponse(at: t, stiffness: pow(2 * .pi / duration, 2), dampingRatio: 1 - bounce)
    }
}
