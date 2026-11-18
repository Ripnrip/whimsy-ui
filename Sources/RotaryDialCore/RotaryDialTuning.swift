import Foundation

/// Shared numbers for the rotary passcode lock.
/// `webports/rotarydial-core.mjs` repeats this table. Change both together.
public enum RotaryDialTuning {
    public static let canvasWidth = 390.0
    public static let canvasHeight = 844.0

    public static let centerX = 195.0
    public static let centerY = 500.0

    public static let outerRadius = 148.0
    public static let faceRadius = 132.0
    public static let holeOrbit = 102.0
    public static let holeRadius = 20.0
    public static let hubRadius = 26.0
    /// Extra points around a hole that still count as a grab.
    public static let hitSlop = 6.0

    public static let holeCount = 10
    /// Ten holes on a twelve-position circle. 30°, radians.
    public static let holeStep = Double.pi / 6
    /// Finger stop, clockwise from 3 o'clock with y down. 36°.
    public static let stopAngle = Double.pi / 5
    /// A full turn of 0, ten steps. The stop will not travel past this.
    public static let maxTravel = holeStep * 10

    /// Still counts as dialed when the hole is this close to the stop.
    public static let commitSlop = holeStep * 0.42

    public static let digitCount = 4

    /// Critically damped return. √400 = 20, so the damping coefficient is exactly 40.
    public static let springStiffness = 400.0
    public static let springDamping = 1.0

    public static let dropDuration = 0.38
    public static let shakeDuration = 0.56
    public static let shakeAmplitude = 16.0
    public static let shakeCycles = 5.0
    /// Reduce Motion holds a tint for this long instead of shaking.
    public static let tintDuration = 0.32
    public static let morphDuration = 0.55
    public static let reduceMorphDuration = 0.28

    public static let dotsY = 156.0
    public static let dotGap = 36.0
    public static let dotRadius = 11.0
    public static let captionY = 214.0

    public static let keySize = 62.0
    public static let keyGap = 16.0
    public static let badgeSize = 128.0

    /// Keypad reading order. -1 is the empty cell, -2 is delete.
    public static let keyOrder: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2]

    public static let defaultCode = "5216"

    public static let restCaption = "Drag a number to the stop"
    public static let wrongCaption = "Wrong code"
    public static let keypadCaption = "Try the keypad"
    public static let unlockedCaption = "Unlocked"
    public static let wrongAnnouncement = "Incorrect, try again"
    public static let unlockedAnnouncement = "Unlocked"

    public static func enteredAnnouncement(_ count: Int) -> String {
        "\(count) of \(digitCount)"
    }

    public static var keypadWidth: Double { keySize * 3 + keyGap * 2 + 48 }
    public static var keypadHeight: Double { keySize * 4 + keyGap * 3 + 64 }

    public static func dotCenter(_ slot: Int) -> Vec2 {
        let span = Double(digitCount - 1) * dotGap
        let x = centerX - span / 2 + Double(slot) * dotGap
        return Vec2(x, dotsY)
    }

    /// Centre of the key for a display digit, or the delete key when `digit` is -2.
    public static func keyCenter(digit: Int) -> Vec2 {
        let index = keyOrder.firstIndex(of: digit) ?? 10
        let column = index % 3
        let row = index / 3
        let pitchX = keySize + keyGap
        let pitchY = keySize + keyGap
        let gridW = keySize * 3 + keyGap * 2
        let gridH = keySize * 4 + keyGap * 3
        let left = centerX - gridW / 2 + keySize / 2
        let top = centerY - gridH / 2 + keySize / 2
        return Vec2(left + Double(column) * pitchX, top + Double(row) * pitchY)
    }
}

/// The plate that matched geometry (and the canvas port) interpolates.
public struct RotaryDialPlate: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var corner: Double

    public init(width: Double, height: Double, corner: Double) {
        self.width = width
        self.height = height
        self.corner = corner
    }

    public static func shape(for face: RotaryDialFace) -> RotaryDialPlate {
        switch face {
        case .dial:
            let d = RotaryDialTuning.outerRadius * 2
            return RotaryDialPlate(width: d, height: d, corner: RotaryDialTuning.outerRadius)
        case .keypad:
            return RotaryDialPlate(width: RotaryDialTuning.keypadWidth,
                                    height: RotaryDialTuning.keypadHeight,
                                    corner: 32)
        case .badge:
            return RotaryDialPlate(width: RotaryDialTuning.badgeSize,
                                    height: RotaryDialTuning.badgeSize,
                                    corner: RotaryDialTuning.badgeSize / 2)
        }
    }

    public static func lerp(_ a: RotaryDialPlate, _ b: RotaryDialPlate, _ t: Double) -> RotaryDialPlate {
        RotaryDialPlate(width: WhimsyMath.lerp(a.width, b.width, t),
                        height: WhimsyMath.lerp(a.height, b.height, t),
                        corner: WhimsyMath.lerp(a.corner, b.corner, t))
    }
}

/// Colours shared with the canvas port, 0…1.
public enum RotaryDialPalette {
    public static let groundR = 0.09, groundG = 0.07, groundB = 0.06
    public static let liftR = 0.20, liftG = 0.15, liftB = 0.11
    public static let paperR = 0.96, paperG = 0.93, paperB = 0.86
    public static let inkR = 0.14, inkG = 0.10, inkB = 0.08
    public static let metalR = 0.28, metalG = 0.22, metalB = 0.18
    public static let brassR = 0.72, brassG = 0.54, brassB = 0.28
    public static let holeR = 0.08, holeG = 0.06, holeB = 0.05
    /// #34C74C
    public static let successR = 52.0 / 255, successG = 199.0 / 255, successB = 76.0 / 255
    /// #D92D20
    public static let errorR = 217.0 / 255, errorG = 45.0 / 255, errorB = 32.0 / 255
}
