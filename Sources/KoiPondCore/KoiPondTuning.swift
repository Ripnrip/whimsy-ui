import Foundation

/// One koi colour. Copied by `webports/koipond-core.mjs`. Components are 0…1.
public struct KoiRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Layout, motion, tail, ripple and palette constants shared with `webports/koipond-core.mjs`.
/// Change both together.
public enum KoiPondTuning {
    public static let sceneWidth = 390.0
    public static let sceneHeight = 844.0

    public static let pondX = 28.0
    public static let pondY = 128.0
    public static let pondWidth = 334.0
    public static let pondHeight = 600.0
    public static let outerInset = 8.0
    /// Head stay this far inside the water line, leaving room for the tail.
    public static let headInset = 36.0

    public static let defaultCount = 6
    public static let maxKoi = 8
    public static let spineCount = 5
    public static let segmentLength = 18.0
    /// Half-width of the body at each spine point, head first. The web port draws the same ribbon.
    public static let bodyWidths: [Double] = [10.5, 13.0, 10.0, 5.5, 1.6]

    public static let fixedStep = 1.0 / 60.0
    public static let maxFrame = 0.1

    /// A press shorter than this never calls the fish in.
    public static let longPress = 0.24
    /// Fish i may leave its lap only after `i` times this, measured from the commit.
    public static let stagger = 0.20

    public static let lapSpeed = 46.0
    public static let seekSpeed = 128.0
    public static let scatterSpeed = 168.0
    public static let scatterDuration = 0.72
    public static let scatterFan = 0.55
    /// Faster than the lap turn, so a release whips the school outward before the burst ends.
    public static let scatterTurnRate = 8.5
    public static let turnRate = 3.4
    public static let arriveRadius = 22.0
    public static let holdRadius = 48.0
    public static let arriveSlow = 70.0
    public static let nibbleGap = 18.0
    public static let bobAmplitude = 6.0
    public static let bobOmega = 8.2
    /// A nibbling head may slide this far in one step to stay on the fingertip.
    /// Farther than that, it leaves the peck and steers, so a moved finger is not a teleport.
    public static let nibbleLeash = 8.0
    /// A nibble fires when the bob sine rises through this value.
    public static let nibbleThreshold = 0.35
    public static let returnCatch = 42.0
    public static let returnTimeout = 3.4
    public static let lapLookahead = 0.55
    public static let orbitMin = 0.36
    public static let orbitMax = 0.70
    /// How far a seeded lap may drift off its even place around the pond, in radians.
    public static let orbitJitter = 0.42
    public static let omegaMin = 0.32
    public static let omegaMax = 0.58

    public static let tailOmega = 8.4
    public static let tailAmplitude = 0.52
    public static let tailLag = 0.62

    /// Reduce Motion multiplies lap, seek, return and the tail clock by this. No scatter burst.
    public static let reduceScale = 0.42
    /// VoiceOver's Feed koi holds the fingertip down for this long, then lets go.
    /// Reduce Motion divides speeds by `reduceScale` and stretches this hold by the same factor,
    /// and will not let go until every koi has pecked (or `feedCap`).
    public static let feedDuration = 3.6
    public static let feedCap = 14.0

    public static let gatherLife = 1.25
    public static let nibbleLife = 0.72
    public static let gatherRadius = 148.0
    public static let nibbleRadius = 34.0
    public static let reduceGatherRadius = 36.0
    public static let reduceNibbleRadius = 14.0
    public static let maxRipples = 14

    public static let defaultSeed: UInt64 = 0x4B6F_694E_6962_2B31

    public static let swimmingValue = "Koi swimming"
    public static let nibblingValue = "Koi nibbling"
    public static let feedAction = "Feed koi"
    public static let title = "Koi"
    public static let hint = "Hold to feed"

    public static let paper = KoiRGB(0.910, 0.945, 0.925)
    public static let waterDeep = KoiRGB(0.047, 0.227, 0.259)
    public static let waterMid = KoiRGB(0.094, 0.431, 0.463)
    public static let waterShallow = KoiRGB(0.306, 0.659, 0.627)
    public static let sand = KoiRGB(0.769, 0.643, 0.471)
    public static let stone = KoiRGB(0.420, 0.455, 0.431)
    public static let lily = KoiRGB(0.180, 0.471, 0.282)
    public static let lilyDark = KoiRGB(0.110, 0.333, 0.196)
    public static let flower = KoiRGB(0.910, 0.471, 0.541)
    public static let finger = KoiRGB(0.941, 0.769, 0.667)
    public static let ink = KoiRGB(0.102, 0.141, 0.149)

    public static let palettes: [KoiPalette] = [
        KoiPalette(body: KoiRGB(0.910, 0.384, 0.165), belly: KoiRGB(1.000, 0.925, 0.839), fin: KoiRGB(0.769, 0.243, 0.125)),
        KoiPalette(body: KoiRGB(0.965, 0.949, 0.918), belly: KoiRGB(1.000, 0.980, 0.953), fin: KoiRGB(0.769, 0.188, 0.165)),
        KoiPalette(body: KoiRGB(0.910, 0.690, 0.243), belly: KoiRGB(1.000, 0.894, 0.667), fin: KoiRGB(0.710, 0.420, 0.110)),
        KoiPalette(body: KoiRGB(0.141, 0.157, 0.188), belly: KoiRGB(0.910, 0.690, 0.243), fin: KoiRGB(0.910, 0.384, 0.165)),
        KoiPalette(body: KoiRGB(0.957, 0.769, 0.306), belly: KoiRGB(1.000, 0.945, 0.780), fin: KoiRGB(0.831, 0.510, 0.141)),
        KoiPalette(body: KoiRGB(0.824, 0.212, 0.188), belly: KoiRGB(0.980, 0.941, 0.910), fin: KoiRGB(0.620, 0.110, 0.125)),
    ]

    /// Lily pads in scene points. Decorative, not part of the simulation.
    public static let lilies: [(x: Double, y: Double, r: Double)] = [
        (86, 246, 30),
        (308, 612, 36),
        (96, 648, 18),
    ]

    public static var pondCenter: Vec2 {
        Vec2(pondX + pondWidth / 2, pondY + pondHeight / 2)
    }

    public static var feedPoint: Vec2 { pondCenter }

    public static var outerRadiusX: Double { pondWidth / 2 - outerInset }
    public static var outerRadiusY: Double { pondHeight / 2 - outerInset }
    public static var headRadiusX: Double { outerRadiusX - headInset }
    public static var headRadiusY: Double { outerRadiusY - headInset }
    public static var fingerRadiusX: Double { headRadiusX - nibbleGap - bobAmplitude }
    public static var fingerRadiusY: Double { headRadiusY - nibbleGap - bobAmplitude }

    public static func clampHead(_ p: Vec2) -> Vec2 {
        clamp(p, rx: headRadiusX, ry: headRadiusY)
    }

    public static func clampFinger(_ p: Vec2) -> Vec2 {
        clamp(p, rx: fingerRadiusX, ry: fingerRadiusY)
    }

    public static func containsOuter(_ p: Vec2, slop: Double = 0) -> Bool {
        contains(p, rx: outerRadiusX + slop, ry: outerRadiusY + slop)
    }

    public static func containsFinger(_ p: Vec2) -> Bool {
        contains(p, rx: fingerRadiusX, ry: fingerRadiusY)
    }

    /// Each point after the head sits exactly `segmentLength` from the one ahead.
    public static func constrain(_ spine: inout [Vec2], heading: Double) {
        guard spine.count >= 2 else { return }
        for i in 1..<spine.count {
            var dx = spine[i].x - spine[i - 1].x
            var dy = spine[i].y - spine[i - 1].y
            var len = (dx * dx + dy * dy).squareRoot()
            if len < 1e-8 {
                dx = -KoiPondMath.cos(heading)
                dy = -KoiPondMath.sin(heading)
                len = 1
            }
            let scale = segmentLength / len
            spine[i].x = spine[i - 1].x + dx * scale
            spine[i].y = spine[i - 1].y + dy * scale
        }
    }

    public static func lapPoint(angle: Double, scale: Double) -> Vec2 {
        let c = pondCenter
        return Vec2(
            c.x + KoiPondMath.cos(angle) * headRadiusX * scale,
            c.y + KoiPondMath.sin(angle) * headRadiusY * scale
        )
    }

    static func clamp(_ p: Vec2, rx: Double, ry: Double) -> Vec2 {
        guard p.x.isFinite, p.y.isFinite, rx > 0, ry > 0 else { return pondCenter }
        let c = pondCenter
        let nx = (p.x - c.x) / rx
        let ny = (p.y - c.y) / ry
        let d2 = nx * nx + ny * ny
        if d2 <= 1 { return p }
        let d = d2.squareRoot()
        return Vec2(c.x + nx / d * rx, c.y + ny / d * ry)
    }

    static func contains(_ p: Vec2, rx: Double, ry: Double) -> Bool {
        guard p.x.isFinite, p.y.isFinite, rx > 0, ry > 0 else { return false }
        let c = pondCenter
        let nx = (p.x - c.x) / rx
        let ny = (p.y - c.y) / ry
        return nx * nx + ny * ny <= 1 + 1e-9
    }
}

public struct KoiPalette: Equatable, Sendable {
    public var body: KoiRGB
    public var belly: KoiRGB
    public var fin: KoiRGB

    public init(body: KoiRGB, belly: KoiRGB, fin: KoiRGB) {
        self.body = body
        self.belly = belly
        self.fin = fin
    }
}
