import Foundation

/// Shared numbers for the louvre vent. The SwiftUI view, the tests and
/// `webports/louvrevent-core.mjs` all read these; the web port copies the values.
public enum LouvreVentTuning {
    public static let sceneWidth = 390.0
    public static let sceneHeight = 844.0

    public static let bladeCount = 7
    public static let minAngle = 0.0
    public static let maxAngle = 70.0

    public static let defaultLower = 60
    public static let defaultUpper = 85
    public static var defaultRange: ClosedRange<Int> { defaultLower...defaultUpper }

    /// Steel frame and the opening the blades sit in. Scene points, y down.
    public static let frameX = 48.0
    public static let frameY = 168.0
    public static let frameWidth = 270.0
    public static let frameHeight = 404.0
    public static let bezel = 18.0
    public static let frameRadius = 26.0
    public static let openingRadius = 10.0

    public static var openingX: Double { frameX + bezel }
    public static var openingY: Double { frameY + bezel }
    public static var openingWidth: Double { frameWidth - bezel * 2 }
    public static var openingHeight: Double { frameHeight - bezel * 2 }

    /// Fraction of each slot the blade face fills when it is closed (angle 0).
    /// The rest is the hairline gap the chamber glows through.
    public static let bladeFaceRatio = 0.92

    /// Displayed angle and glow chase the set point on this spring.
    /// Reduce Motion snaps, so the spring never runs.
    public static let stiffness = 220.0
    public static let dampingRatio = 0.92
    public static let settleTolerance = 0.0008

    /// Traveling glint on top of the resting highlight. Envelope rises while
    /// the finger is down or the spring is moving, then falls. Reduce Motion
    /// keeps the envelope at 0, so the highlight does not sweep.
    public static let sweepRise = 6.5
    public static let sweepFall = 2.4
    /// Cycles of the triangle wave per second, scaled by the envelope.
    public static let sweepOmega = 1.7
    public static let specularStart = 0.18
    public static let specularTravel = 0.62
    public static let specularBladePhase = 0.04
    public static let specularSweepAmplitude = 0.10
    /// Specular brightness. `floor + gain * glow.intensity`.
    public static let specularFloor = 0.48
    public static let specularGain = 0.52

    /// Deep orange at the cool end, white-hot at the hot end.
    /// Every channel and the intensity rise with temperature.
    public static let coolRed = 0.62
    public static let coolGreen = 0.16
    public static let coolBlue = 0.02
    public static let coolIntensity = 0.42
    public static let hotRed = 1.0
    public static let hotGreen = 0.97
    public static let hotBlue = 0.91
    public static let hotIntensity = 1.0

    public static let wordmark = "LOUVRE"
    public static let caption = "SET POINT"
    public static let wordmarkY = 108.0
    public static let captionY = 136.0
    public static let readoutY = 652.0
    public static let railX = 344.0

    public static let accessibilityLabel = "Louvre vent thermostat"
    public static let accessibilityHint = "Swipe up or down to change the set point by one degree."

    public static func accessibilityValue(temperature: Int) -> String {
        "\(temperature) degrees"
    }
}

/// One sample of the chamber glow, in sRGB. `intensity` is how hard it burns, 0…1.
public struct LouvreGlow: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var intensity: Double

    public init(red: Double, green: Double, blue: Double, intensity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.intensity = intensity
    }
}

/// One blade's slot in scene points. `angle` is the X-axis rotation in degrees.
/// `projectedHeight` is the foreshortened face (`faceHeight` × cos(angle)).
/// `specular` is where the highlight sits on the face, 0 at the top edge and 1 at the bottom.
public struct LouvreBladeSlot: Equatable, Sendable {
    public var index: Int
    public var x: Double
    public var slotTop: Double
    public var width: Double
    public var slotHeight: Double
    public var faceHeight: Double
    public var projectedHeight: Double
    public var centerX: Double
    public var centerY: Double
    public var specular: Double
    public var angle: Double

    public var gap: Double { (slotHeight - projectedHeight) * 0.5 }

    public init(
        index: Int,
        x: Double,
        slotTop: Double,
        width: Double,
        slotHeight: Double,
        faceHeight: Double,
        projectedHeight: Double,
        centerX: Double,
        centerY: Double,
        specular: Double,
        angle: Double
    ) {
        self.index = index
        self.x = x
        self.slotTop = slotTop
        self.width = width
        self.slotHeight = slotHeight
        self.faceHeight = faceHeight
        self.projectedHeight = projectedHeight
        self.centerX = centerX
        self.centerY = centerY
        self.specular = specular
        self.angle = angle
    }
}

public enum LouvreVentEvent: Equatable, Sendable {
    /// The set point landed on this degree. A jump of three degrees emits three ticks.
    case tick(Int)
}
