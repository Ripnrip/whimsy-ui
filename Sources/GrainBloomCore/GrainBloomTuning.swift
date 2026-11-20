import Foundation

/// Constants for the grain-bloom placeholder. The same numbers are copied in
/// `webports/grainbloom-core.mjs` and printed at the top of the golden trace.
public enum GrainBloomTuning {
    public static let stageWidth = 390.0
    public static let stageHeight = 844.0
    public static let wakeDuration = 0.90
    public static let resolveDuration = 1.40
    public static let settleDuration = 0.35
    public static let reduceDuration = 0.28
    public static let lattice = 32
    public static let maxBlur = 18.0
    public static let defaultSeed: UInt64 = 0x6B1E_B10B
    public static let cellSizes: [Double] = [16, 8, 4, 2, 1]

    /// Conventional Bayer 4×4, row-major. Thresholds are 0...15.
    public static let bayer4: [Int] = [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5,
    ]

    public static let defaultPalette: [GrainBloomRGB] = [
        GrainBloomRGB(r: 0.96, g: 0.55, b: 0.38),
        GrainBloomRGB(r: 0.36, g: 0.34, b: 0.78),
        GrainBloomRGB(r: 0.22, g: 0.66, b: 0.62),
        GrainBloomRGB(r: 0.93, g: 0.78, b: 0.36),
    ]

    public static let generatingValue = "Generating image"
    public static let readyValue = "Image ready"
}

public struct GrainBloomRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}
