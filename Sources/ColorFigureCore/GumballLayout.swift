import Foundation

/// The five body colours.
public enum GumballSwatch: String, CaseIterable, Sendable {
    case tomato, mustard, mint, cobalt, blush

    public var base: UInt32 {
        switch self {
        case .tomato: return 0xE4573D
        case .mustard: return 0xF0B429
        case .mint: return 0x7CCBA2
        case .cobalt: return 0x4F7FD0
        case .blush: return 0xF2A7BC
        }
    }
    public var palette: FigurePalette { FigurePalette(base: base) }
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The gumball colours (candy, not body).
public enum GumballCandy {
    public static let hexes: [UInt32] = [0xE8465A, 0xF6C945, 0x56BE8A, 0x4A86D6, 0xF08DB5, 0xF5873A]
    public static func color(_ i: Int) -> FigureColor { FigureColor(hex: hexes[((i % hexes.count) + hexes.count) % hexes.count]) }
}

/// The gumballs in the globe: seeded positions in the lower part of the glass, settled with a minimum spacing.
public struct GumballPile: Sendable {
    public struct Ball: Sendable { public var centre: Vec3; public var colorIndex: Int }
    public var balls: [Ball]

    public static let count = 34
    public static let ballRadius = 3.1

    public static func make(seed: UInt64 = 2718, count: Int = GumballPile.count) -> GumballPile {
        var rng = SeededRandom(seed: seed)
        let c = GumballLayout.globeCentre
        let inner = GumballLayout.globeRadius - ballRadius - 0.4
        let zMax = c.z + 3.0
        var placed: [Vec3] = []
        var attempts = 0
        while placed.count < count && attempts < 20000 {
            attempts += 1
            let p = Vec3(rng.uniform(-inner...inner), rng.uniform(-inner...inner), rng.uniform(-inner...inner)) + c
            if (p - c).length > inner || p.z > zMax { continue }
            if placed.contains(where: { ($0 - p).length < ballRadius * 1.9 }) { continue }
            placed.append(p)
        }
        // Lowest first: the lowest ball is the one that drops next.
        placed.sort { $0.z != $1.z ? $0.z < $1.z : ($0.x != $1.x ? $0.x < $1.x : $0.y < $1.y) }
        let balls = placed.map { Ball(centre: $0, colorIndex: Int(rng.uniform(0...5.999999))) }
        return GumballPile(balls: balls)
    }
}

/// Everything about the machine's geometry: where things are, in world units (x is the front).
public enum GumballLayout {
    // Case
    public static let slabMin = Vec3(-19, -19, 0), slabMax = Vec3(27, 19, 4)
    public static let cabinetMin = Vec3(-17, -17, 4), cabinetMax = Vec3(17, 17, 52)
    public static let globeCentre = Vec3(0, 0, 78)
    public static let globeRadius = 22.0
    public static let frontX = 17.0
    // Crank: the hub sits on the front, the arm swings in the y-z plane about it.
    public static let crankPivot = Vec3(0, 0, 24)
    public static let crankArmLength = 8.0
    public static let knobRadius = 2.1
    public static let knobX = 24.5
    public static let crankHitRadius = 9.0
    public static let ratchetX = 13.6
    // Gear train: crank shaft -> pinion -> wheel, 4 : 1
    public static let gearRatio = 4.0
    public static let wheelCentreZ = 36.0
    public static let wheelRadius = 9.0
    public static let pocketRadius = 6.4
    public static let pocketCount = 4
    public static let wheelX = (4.4, 7.0)
    // Flap
    public static let flapPivot = Vec3(17.65, 0, 13.6)
    public static let flapMaxAngle = 50.0 * Double.pi / 180
    // Coin
    public static let coinStart = Vec3(26, 0, 41.5)
    public static let coinSlotX = 14.2
    public static let coinRestZ = 33.8
    public static let coinRadius = 2.6
    // Paths
    /// The gumball's route: pocket at the wheel's side, down the chute, out of the flap, to rest on the slab.
    public static let ballPath: [Vec3] = [
        Vec3(7.6, 6.4, 36.0), Vec3(9.9, 6.4, 31.0), Vec3(9.9, 6.4, 20.0), Vec3(12.0, 5.2, 13.0),
        Vec3(14.8, 2.0, 9.2), Vec3(17.9, 0.0, 8.0), Vec3(20.4, 0.0, 6.6), Vec3(23.4, 0.0, 6.6),
    ]
    /// Index in `ballPath` where the ball leaves through the flap.
    public static let flapIndex = 5
    public static let ballRadius = 2.6

    /// The crank handle's direction for an angle (0 hangs straight down; increasing turns clockwise seen from the front).
    public static func crankDirection(_ a: Double) -> Vec3 { Vec3(0, -sin(a), -cos(a)) }
    public static func knobCentre(angle a: Double) -> Vec3 {
        crankPivot + crankDirection(a) * (crankArmLength + 0.3) + Vec3(knobX, 0, 0)
    }
    /// Where the pocket `k` sits (angle measured from the top toward +y), with the wheel turned by `wheel` radians.
    public static func pocketCentre(_ k: Int, wheel: Double) -> Vec3 {
        let th = wheel + Double(k) * 2 * Double.pi / Double(pocketCount)
        return Vec3(wheelX.1, pocketRadius * sin(th), wheelCentreZ + pocketRadius * cos(th))
    }

    // Solid ids (stable, so a part's wobble never changes as other things come and go)
    enum ID {
        static let slab = 1, lip = 2, cabinet = 3, collar = 4, cap = 5, knob = 6, coinPlate = 7, coinSlot = 8, crankHousing = 9
        static let crankHub = 10, crankArm = 11, crankKnob = 12, recess = 13, flap = 14
        static let shaft = 20, pinion = 21, pinionMark = 22, wheel = 23, hopper = 24, mechLeft = 25, mechRight = 26, mechBack = 27
        static let mechFloor = 28, ratchet = 29, ratchetNotch = 30, pawl = 31, flapTab = 32, springBracket = 33
        static let pocket = 40      // 40...43
        static let chute = 50       // 50...53
        static let coin = 60        // 60...63
        static let spring = 70
        static let globe = 80
        static let pocketBall = 90, travelBall = 91, prize = 92, reloadBall = 93
        static let pile = 200
    }

    /// The state the scene is drawn in.
    public struct Pose: Sendable {
        public var crank: Double = 0
        public var wheel: Double = 0
        public var pawl: Double = 0           // 0 locked, 1 released
        public var flap: Double = 0           // 0 shut, 1 fully open
        public var coins: [Vec3] = []         // newest first; the first may be mid-air
        public var sprites: [FigureSprite] = []
        public var pileSkip: Int = 0          // gumballs gone from the bottom of the pile
        public init() {}
    }

    public static func scene(pose: Pose, swatch: GumballSwatch, pile: GumballPile, seeThrough: Double) -> FigureScene {
        let body = swatch.palette
        var sc = FigureScene()
        sc.seeThrough = seeThrough
        typealias S = FigureShapes
        func box(_ id: Int, _ part: String, _ layer: FigureLayer, _ pal: FigurePalette, _ lo: Vec3, _ hi: Vec3) -> FigureSolid {
            S.box(id: id, part: part, layer: layer, palette: pal, min: lo, max: hi)
        }
        // Outside
        sc.solids.append(box(ID.slab, "base", .hardware, .charcoal, slabMin, slabMax))
        sc.solids.append(box(ID.lip, "lip", .hardware, .charcoal, Vec3(25.6, -8.5, 4), Vec3(27, 8.5, 6.2)))
        sc.solids.append(box(ID.cabinet, "cabinet", .shell, body, cabinetMin, cabinetMax))
        sc.solids.append(S.cylinder(id: ID.collar, part: "collar", layer: .hardware, palette: .metal, axis: .z, centre: (0, 0), from: 52, to: 56, radius: 16, segments: 18))
        sc.solids.append(S.cylinder(id: ID.cap, part: "cap", layer: .hardware, palette: body, axis: .z, centre: (0, 0), from: 100, to: 104, radius: 10, segments: 18))
        sc.solids.append(S.cylinder(id: ID.knob, part: "capKnob", layer: .hardware, palette: .metal, axis: .z, centre: (0, 0), from: 104, to: 107, radius: 3.5, segments: 12))
        sc.solids.append(box(ID.coinPlate, "coinPlate", .hardware, .metal, Vec3(17, -6.5, 33), Vec3(18.2, 6.5, 49)))
        sc.solids.append(box(ID.coinSlot, "coinSlot", .hardware, .charcoal, Vec3(18.2, -0.6, 38), Vec3(18.5, 0.6, 45)))
        sc.solids.append(S.cylinder(id: ID.crankHousing, part: "crankHousing", layer: .hardware, palette: .metal, axis: .x, centre: (0, crankPivot.z), from: 17, to: 19.2, radius: 6.5, segments: 16))
        sc.solids.append(S.cylinder(id: ID.crankHub, part: "crankHub", layer: .hardware, palette: .metal, axis: .x, centre: (0, crankPivot.z), from: 19.2, to: 21, radius: 2.6, segments: 12))
        let arm = box(ID.crankArm, "crankArm", .hardware, .metal, Vec3(21, -1.2, crankPivot.z - crankArmLength), Vec3(22.6, 1.2, crankPivot.z + 1.2))
            .rotated(.x, about: crankPivot, by: -pose.crank)
        sc.solids.append(arm)
        let knobZ = crankPivot.z - crankArmLength - 0.3
        sc.solids.append(S.cylinder(id: ID.crankKnob, part: "crankKnob", layer: .hardware, palette: body, axis: .x, centre: (0, knobZ), from: 22.6, to: knobX + 1.9, radius: knobRadius, segments: 12)
            .rotated(.x, about: crankPivot, by: -pose.crank))
        sc.solids.append(box(ID.recess, "recess", .hardware, .charcoal, Vec3(17, -6.4, 4), Vec3(17.2, 6.4, 14.2)))
        sc.solids.append(box(ID.flap, "flap", .hardware, .metal, Vec3(17.3, -5.8, 4.5), Vec3(18.0, 5.8, 13.6))
            .rotated(.y, about: flapPivot, by: -pose.flap * flapMaxAngle))
        // Inside
        let wz = wheelCentreZ
        sc.solids.append(S.cylinder(id: ID.shaft, part: "shaft", layer: .interior, palette: .metal, axis: .x, centre: (0, crankPivot.z), from: 3.8, to: 19.2, radius: 1.1, segments: 10))
        sc.solids.append(S.cylinder(id: ID.pinion, part: "pinion", layer: .interior, palette: .brass, axis: .x, centre: (0, crankPivot.z), from: wheelX.0, to: wheelX.1, radius: 3, segments: 14))
        sc.solids.append(box(ID.pinionMark, "pinionMark", .interior, .charcoal, Vec3(wheelX.1, -0.4, crankPivot.z), Vec3(wheelX.1 + 0.3, 0.4, crankPivot.z + 2.8))
            .rotated(.x, about: crankPivot, by: -pose.crank))
        sc.solids.append(S.cylinder(id: ID.wheel, part: "wheel", layer: .interior, palette: .ceramic, axis: .x, centre: (0, wz), from: wheelX.0, to: wheelX.1, radius: wheelRadius, segments: 20))
        for k in 0..<pocketCount {
            let c = pocketCentre(k, wheel: -pose.wheel)
            sc.solids.append(S.cylinder(id: ID.pocket + k, part: "pocket", layer: .interior, palette: .charcoal, axis: .x, centre: (c.y, c.z), from: wheelX.1, to: wheelX.1 + 0.35, radius: 2.9, segments: 10))
        }
        sc.solids.append({ () -> FigureSolid in
            var h = S.rod(id: ID.hopper, part: "hopper", layer: .interior, palette: .glass, from: Vec3(0, 0, 56), to: Vec3(6.4, 0, 48.2), halfWidth: 3)
            h.translucency = 0.55
            return h
        }())
        sc.solids.append(box(ID.mechLeft, "coinMech", .interior, .metal, Vec3(12.5, -4, 30.6), Vec3(15.8, -3.4, 46)))
        sc.solids.append(box(ID.mechRight, "coinMech", .interior, .metal, Vec3(12.5, 3.4, 30.6), Vec3(15.8, 4, 46)))
        sc.solids.append(box(ID.mechBack, "coinMech", .interior, .metal, Vec3(12.5, -4, 30.6), Vec3(13.1, 4, 46)))
        sc.solids.append(box(ID.mechFloor, "coinMech", .interior, .metal, Vec3(12.5, -4, 30.6), Vec3(15.8, 4, 31.2)))
        sc.solids.append(S.cylinder(id: ID.ratchet, part: "ratchet", layer: .interior, palette: .brass, axis: .x, centre: (0, crankPivot.z), from: 12.8, to: 14.5, radius: 4.3, segments: 14))
        sc.solids.append(box(ID.ratchetNotch, "ratchet", .interior, .charcoal, Vec3(14.5, -0.9, crankPivot.z + 3.2), Vec3(14.75, 0.9, crankPivot.z + 4.4))
            .rotated(.x, about: crankPivot, by: -pose.crank))
        sc.solids.append(box(ID.pawl, "pawl", .interior, .metal, Vec3(13.1, -0.6, 26.6), Vec3(14.2, 0.6, 30.6))
            .rotated(.y, about: Vec3(13.65, 0, 30.6), by: -pose.pawl * 40 * Double.pi / 180))
        sc.solids.append(box(ID.springBracket, "springBracket", .interior, .metal, Vec3(14.8, -1, 19), Vec3(17, 1, 20.2)))
        sc.solids.append(box(ID.flapTab, "flapTab", .interior, .metal, Vec3(14.8, -0.8, 13.0), Vec3(17.3, 0.8, 14.2))
            .rotated(.y, about: flapPivot, by: -pose.flap * flapMaxAngle))
        // The chute tube.
        let tube: [Vec3] = [Vec3(9.9, 6.4, 26), ballPath[2], ballPath[3], ballPath[4], Vec3(17.0, 0.4, 8.4)]
        for i in 0..<(tube.count - 1) {
            var r = FigureShapes.rod(id: ID.chute + i, part: "chute", layer: .interior, palette: .glass, from: tube[i], to: tube[i + 1], halfWidth: 2.9)
            r.translucency = 0.5
            sc.solids.append(r)
        }
        // The flap's return spring: a coil from the bracket down to the tab.
        let a = Vec3(15.0, 0, 19.0)
        let c = cos(pose.flap * flapMaxAngle), s = sin(pose.flap * flapMaxAngle)
        let b = Vec3(flapPivot.x - 2.75 * c, 0, flapPivot.z - 2.75 * s)
        let axis = (b - a).normalized
        let e1 = Vec3(0, 1, 0), e2 = axis.cross(e1).normalized
        var coil: [Vec3] = []
        let turns = 7, per = 8
        for i in 0...(turns * per) {
            let t = Double(i) / Double(turns * per)
            let th = 2 * Double.pi * Double(turns) * t
            coil.append(a + (b - a) * t + (e1 * cos(th) + e2 * sin(th)) * 0.8)
        }
        sc.wires.append(FigureWire(id: ID.spring, layer: .interior, points: coil, width: 0.4, color: FigureColor(hex: 0x6C6F72)))
        // Coins: a newest coin (possibly in flight) and a couple of older ones resting in the box.
        for (j, p) in pose.coins.enumerated() {
            let layer: FigureLayer = p.x >= 18.9 ? .hardware : .interior
            sc.solids.append(S.cylinder(id: ID.coin + j, part: "coin", layer: layer, palette: .brass, axis: .y, centre: (p.x, p.z), from: p.y - 0.35, to: p.y + 0.35, radius: coinRadius, segments: 14))
        }
        let fades: [String: Double] = ["coinPlate": 0.28, "coinSlot": 0.5, "crankHousing": 0.3, "recess": 0.3, "flap": 0.6, "lip": 0.6, "collar": 0.5, "cap": 0.5]
        for i in sc.solids.indices { if let f = fades[sc.solids[i].part] { sc.solids[i].xrAlpha = f } }
        sc.sprites = pose.sprites
        // The globe and the pile in it.
        var balls: [FigureSprite] = []
        for (i, b) in pile.balls.enumerated() where i >= pose.pileSkip {
            balls.append(FigureSprite(id: ID.pile + i, layer: .hardware, centre: b.centre, radius: GumballPile.ballRadius, color: GumballCandy.color(b.colorIndex)))
        }
        sc.globe = FigureGlobe(id: ID.globe, centre: globeCentre, radius: globeRadius, balls: balls)
        // Shadow: the slab, the case, the collar and the top of the globe.
        var sp: [Vec3] = []
        for x in [slabMin.x, slabMax.x] { for y in [slabMin.y, slabMax.y] { sp.append(Vec3(x, y, 0)); sp.append(Vec3(x, y, 4)) } }
        for x in [cabinetMin.x, cabinetMax.x] { for y in [cabinetMin.y, cabinetMax.y] { sp.append(Vec3(x, y, 52)) } }
        for i in 0..<12 {
            let th = 2 * Double.pi * Double(i) / 12
            sp.append(Vec3(globeRadius * cos(th) * 0.9, globeRadius * sin(th) * 0.9, 78))
            sp.append(Vec3(8 * cos(th), 8 * sin(th), 104))
        }
        sc.shadowPoints = sp
        return sc
    }
}
