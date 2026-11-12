import Foundation

/// A colour the core can describe without SwiftUI. Components are 0…1.
public struct RubberBandRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// One generated mark, in unit card space (origin top-left, y down). Centres and sizes are
/// fractions of the card; `rotation` is radians clockwise-positive; `corner` is a fraction of
/// the card's shorter side.
public enum RubberBandMark: Equatable, Sendable {
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double, color: RubberBandRGB, alpha: Double)
    case roundRect(cx: Double, cy: Double, width: Double, height: Double, corner: Double, color: RubberBandRGB, alpha: Double)
    case capsule(cx: Double, cy: Double, width: Double, height: Double, rotation: Double, color: RubberBandRGB, alpha: Double)
}

/// Copy and generated artwork for one slot in the hand. Artwork is marks only — no images.
public struct RubberBandCardSpec: Equatable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    public var kicker: String
    public var detail: String
    public var paper: RubberBandRGB
    public var ink: RubberBandRGB
    public var marks: [RubberBandMark]
    public var id: Int { index }
}

/// The five cards the hand ships with. Slot `i` always wears design `i`, so a caller who
/// only replaces the words still gets five distinct pictures.
public enum RubberBandCatalog {
    public static let cards: [RubberBandCardSpec] = [
        lumen, terrace, citrus, nightTrain, botanic,
    ]

    public static func spec(_ index: Int) -> RubberBandCardSpec {
        cards[RubberBandLayout.clamped(index)]
    }

    private static let lumen = RubberBandCardSpec(
        index: 0,
        title: "Lumen",
        kicker: "FIELD NOTES",
        detail: "A band of colour that only shows after the lamps along the ridge go out.",
        paper: RubberBandRGB(0.09, 0.10, 0.18),
        ink: RubberBandRGB(0.93, 0.95, 0.98),
        marks: [
            .ellipse(cx: 0.74, cy: 0.16, rx: 0.075, ry: 0.075, color: RubberBandRGB(0.96, 0.93, 0.84), alpha: 1),
            .ellipse(cx: 0.77, cy: 0.15, rx: 0.060, ry: 0.060, color: RubberBandRGB(0.09, 0.10, 0.18), alpha: 1),
            .capsule(cx: 0.46, cy: 0.30, width: 0.92, height: 0.09, rotation: -0.22, color: RubberBandRGB(0.28, 0.82, 0.74), alpha: 0.90),
            .capsule(cx: 0.50, cy: 0.40, width: 0.78, height: 0.075, rotation: 0.10, color: RubberBandRGB(0.93, 0.42, 0.62), alpha: 0.88),
            .capsule(cx: 0.48, cy: 0.50, width: 0.64, height: 0.055, rotation: -0.06, color: RubberBandRGB(0.98, 0.80, 0.42), alpha: 0.85),
        ]
    )

    private static let terrace = RubberBandCardSpec(
        index: 1,
        title: "Terrace",
        kicker: "AFTERNOON",
        detail: "Stone steps that hold the last of the heat, and a sun that has not quite left.",
        paper: RubberBandRGB(0.95, 0.86, 0.73),
        ink: RubberBandRGB(0.29, 0.17, 0.11),
        marks: [
            .ellipse(cx: 0.74, cy: 0.18, rx: 0.09, ry: 0.09, color: RubberBandRGB(0.93, 0.52, 0.20), alpha: 1),
            .roundRect(cx: 0.40, cy: 0.32, width: 0.42, height: 0.075, corner: 0.035, color: RubberBandRGB(0.55, 0.34, 0.24), alpha: 1),
            .roundRect(cx: 0.46, cy: 0.42, width: 0.58, height: 0.075, corner: 0.035, color: RubberBandRGB(0.78, 0.50, 0.32), alpha: 1),
            .roundRect(cx: 0.52, cy: 0.52, width: 0.74, height: 0.075, corner: 0.035, color: RubberBandRGB(0.86, 0.62, 0.40), alpha: 1),
        ]
    )

    private static let citrus = RubberBandCardSpec(
        index: 2,
        title: "Citrus",
        kicker: "MARKET",
        detail: "Three fruits, one leaf, and a paper bag that will not quite close.",
        paper: RubberBandRGB(0.98, 0.96, 0.90),
        ink: RubberBandRGB(0.55, 0.24, 0.09),
        marks: [
            .ellipse(cx: 0.38, cy: 0.40, rx: 0.16, ry: 0.16, color: RubberBandRGB(0.93, 0.48, 0.12), alpha: 1),
            .ellipse(cx: 0.64, cy: 0.42, rx: 0.14, ry: 0.14, color: RubberBandRGB(0.55, 0.70, 0.24), alpha: 1),
            .ellipse(cx: 0.52, cy: 0.24, rx: 0.11, ry: 0.11, color: RubberBandRGB(0.92, 0.40, 0.42), alpha: 1),
            .capsule(cx: 0.70, cy: 0.16, width: 0.16, height: 0.055, rotation: -0.7, color: RubberBandRGB(0.28, 0.52, 0.26), alpha: 1),
            .capsule(cx: 0.66, cy: 0.20, width: 0.04, height: 0.02, rotation: 0.4, color: RubberBandRGB(0.36, 0.28, 0.14), alpha: 1),
        ]
    )

    private static let nightTrain = RubberBandCardSpec(
        index: 3,
        title: "Night Train",
        kicker: "PLATFORM 4",
        detail: "Windows ticking past in the dark, each one a room with the lamp still on.",
        paper: RubberBandRGB(0.07, 0.08, 0.13),
        ink: RubberBandRGB(0.96, 0.91, 0.80),
        marks: [
            .roundRect(cx: 0.28, cy: 0.34, width: 0.16, height: 0.22, corner: 0.04, color: RubberBandRGB(0.98, 0.78, 0.42), alpha: 0.95),
            .roundRect(cx: 0.50, cy: 0.34, width: 0.16, height: 0.22, corner: 0.04, color: RubberBandRGB(0.98, 0.62, 0.38), alpha: 0.95),
            .roundRect(cx: 0.72, cy: 0.34, width: 0.16, height: 0.22, corner: 0.04, color: RubberBandRGB(0.86, 0.78, 0.55), alpha: 0.92),
            .roundRect(cx: 0.28, cy: 0.34, width: 0.10, height: 0.16, corner: 0.02, color: RubberBandRGB(0.16, 0.18, 0.26), alpha: 0.28),
            .capsule(cx: 0.50, cy: 0.52, width: 0.84, height: 0.018, rotation: 0.04, color: RubberBandRGB(0.75, 0.72, 0.62), alpha: 0.85),
            .ellipse(cx: 0.18, cy: 0.18, rx: 0.035, ry: 0.035, color: RubberBandRGB(0.98, 0.86, 0.55), alpha: 1),
        ]
    )

    private static let botanic = RubberBandCardSpec(
        index: 4,
        title: "Botanic",
        kicker: "GLASSHOUSE",
        detail: "Leaves made of ellipses, the way a stencil remembers a plant it once held.",
        paper: RubberBandRGB(0.89, 0.93, 0.86),
        ink: RubberBandRGB(0.13, 0.32, 0.22),
        marks: [
            .roundRect(cx: 0.50, cy: 0.48, width: 0.028, height: 0.30, corner: 0.02, color: RubberBandRGB(0.24, 0.42, 0.28), alpha: 1),
            .capsule(cx: 0.36, cy: 0.34, width: 0.28, height: 0.09, rotation: -0.9, color: RubberBandRGB(0.36, 0.62, 0.38), alpha: 1),
            .capsule(cx: 0.66, cy: 0.30, width: 0.30, height: 0.10, rotation: 0.7, color: RubberBandRGB(0.22, 0.50, 0.36), alpha: 1),
            .capsule(cx: 0.34, cy: 0.48, width: 0.26, height: 0.08, rotation: -0.45, color: RubberBandRGB(0.48, 0.70, 0.40), alpha: 1),
            .ellipse(cx: 0.62, cy: 0.50, rx: 0.045, ry: 0.045, color: RubberBandRGB(0.85, 0.42, 0.38), alpha: 1),
        ]
    )
}
