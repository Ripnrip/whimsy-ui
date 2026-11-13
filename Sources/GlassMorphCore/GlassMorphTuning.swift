import Foundation

/// Shared numbers for the glass pay morph.
/// `webports/glassmorph-core.mjs` repeats this table. Change both together.
public enum GlassMorphTuning {
    public static let canvasWidth = 390.0
    public static let canvasHeight = 844.0

    /// The card and the pill share a centre, so the glass condenses in place.
    public static let stageCenter = Vec2(195, 400)

    public static let cardWidth = 308.0
    public static let cardHeight = 420.0
    public static let cardCorner = 32.0
    /// −3°, the resting lean. Negative is counter-clockwise on a y-down screen.
    public static let cardTilt = -3.0 * Double.pi / 180.0

    public static let pillWidth = 136.0
    public static let pillHeight = 56.0
    public static let pillCorner = 28.0

    /// Backdrop orbs, in stage points. They sit on the card and spill past its edges.
    public static let amberRest = Vec2(98, 258)
    public static let amberRestRadius = 88.0
    public static let amberRestBlur = 18.0
    public static let redRest = Vec2(322, 548)
    public static let redRestRadius = 50.0
    public static let redRestBlur = 14.0

    /// The two-dot mark inside the settled pill. 22 pt between centres.
    public static let amberLogo = Vec2(184, 400)
    public static let amberLogoRadius = 8.0
    public static let redLogo = Vec2(206, 400)
    public static let redLogoRadius = 7.0
    public static let logoBlur = 0.0

    /// Morph spring, under-damped so the pill overshoots and settles.
    public static let morphStiffness = 170.0
    public static let morphDamping = 0.75
    /// Unit progress (and the lights, which follow it) count as settled inside this band.
    public static let settleTolerance = 0.004

    /// Seconds the pill holds after the lights settle, then the half-turn.
    public static let holdDuration = 1.0
    /// Seconds of the opening half-turn. The flip runs 0 → π across this interval.
    public static let unfoldDuration = 0.45
    /// Reduce Motion crossfade, each way.
    public static let fadeDuration = 0.28
    /// Radians around π/2 across which the edge glint fades in.
    public static let edgeWidth = 0.5

    public static let substep = 1.0 / 240.0
    public static let maxFrame = 0.1

    public static let payButtonWidth = 168.0
    public static let payButtonHeight = 48.0
    /// Pay button centre in card-local points (origin at the card centre, +y down).
    public static let payButtonLocal = Vec2(0, 150)
    public static let brandLocalY = -158.0
    public static let amountLocalY = -40.0
    public static let captionLocalY = 16.0

    public static let brandSize = 13.0
    public static let amountSize = 54.0
    public static let captionSize = 15.0
    public static let paySize = 17.0

    public static let defaultAmount = "$48.00"
    public static let defaultLabel = "Solune"
    public static let payTitle = "Pay"
    public static let caption = "Glass wallet"
    public static let announcement = "Payment complete"

    public static let readyValue = "Ready"
    public static let payingValue = "Paying"
    public static let paidValue = "Paid"
    public static let openingValue = "Opening"

    public static let amber = GlassRGB(red: 1, green: 176.0 / 255.0, blue: 64.0 / 255.0)
    public static let red = GlassRGB(red: 1, green: 59.0 / 255.0, blue: 78.0 / 255.0)
    public static let backgroundTop = GlassRGB(red: 7.0 / 255.0, green: 9.0 / 255.0, blue: 20.0 / 255.0)
    public static let backgroundBottom = GlassRGB(red: 22.0 / 255.0, green: 14.0 / 255.0, blue: 34.0 / 255.0)
    public static let ink = GlassRGB(red: 18.0 / 255.0, green: 20.0 / 255.0, blue: 31.0 / 255.0)

    public static var payButton: GlassRect {
        GlassRect(center: payButtonLocal, width: payButtonWidth, height: payButtonHeight)
    }
}

/// A colour the core can carry without SwiftUI. Components are 0…1.
public struct GlassRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// An axis-aligned rectangle in some local space. `contains` counts the boundary.
public struct GlassRect: Equatable, Sendable {
    public var center: Vec2
    public var width: Double
    public var height: Double

    public init(center: Vec2, width: Double, height: Double) {
        self.center = center
        self.width = width
        self.height = height
    }

    public func contains(_ point: Vec2) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        return abs(point.x - center.x) <= width / 2 && abs(point.y - center.y) <= height / 2
    }
}
