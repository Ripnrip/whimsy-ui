import Foundation

/// The glyph strip under an opened specimen.
public enum GlyphStrip {
    public static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    public static let lowercase = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
    public static let digits = Array("0123456789").map(String.init)
    public static let punctuation = Array("&?!@#%*()$€£.,:;'\"").map(String.init)
    /// Everything, in strip order.
    public static var all: [String] { uppercase + lowercase + digits + punctuation }
}

/// Editable state of the detail view: sample text, size and a weight slider that snaps to the
/// weights the family really has.
public struct SpecimenDetailState: Equatable, Sendable {
    public static let defaultSample = "Sphinx of black quartz, judge my vow."
    public static let maxSampleLength = 80
    public static let sizeRange: ClosedRange<Double> = 18...120

    public let specimen: FontSpecimen
    /// What the user typed (sanitised). May be empty; see ``displayText``.
    public private(set) var sampleText: String
    public private(set) var size: Double
    /// Slider position, 0…1.
    public private(set) var weightPosition: Double
    /// Increments each time the slider lands on a different weight (bind a haptic to it).
    public private(set) var weightSteps = 0

    public init(specimen: FontSpecimen, sampleText: String = SpecimenDetailState.defaultSample, size: Double = 44) {
        self.specimen = specimen
        self.sampleText = Self.sanitize(sampleText)
        self.size = Self.clampSize(size)
        self.weightPosition = Self.position(of: specimen.displayWeight, in: specimen.weights)
    }

    /// The text to render: the sample, or the pangram when the field is empty.
    public var displayText: String { sampleText.isEmpty ? Self.defaultSample : sampleText }

    /// The weight the slider currently selects.
    public var weight: FontWeightStep { Self.weight(at: weightPosition, in: specimen.weights) }

    /// Number of slider detents (1 means the slider is disabled: the family has one weight).
    public var weightStops: Int { specimen.weights.count }

    public mutating func setSampleText(_ text: String) { sampleText = Self.sanitize(text) }
    public mutating func setSize(_ s: Double) { size = Self.clampSize(s) }

    /// Moves the weight slider. Returns the haptic event when the selected weight changed.
    @discardableResult
    public mutating func setWeightPosition(_ p: Double) -> FontHapticEvent? {
        guard p.isFinite else { return nil }
        let before = weight
        weightPosition = min(max(p, 0), 1)
        guard weight != before else { return nil }
        weightSteps += 1
        return .weightStep
    }

    /// Snaps the slider onto the detent of the current weight (call on release).
    public mutating func snapWeight() { weightPosition = Self.position(of: weight, in: specimen.weights) }

    /// Newlines become spaces; trimmed to ``maxSampleLength`` characters.
    public static func sanitize(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return String(flat.prefix(maxSampleLength))
    }

    static func clampSize(_ s: Double) -> Double {
        guard s.isFinite else { return 44 }
        return min(max(s, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// Detent `round(p · (n − 1))`.
    public static func weight(at p: Double, in weights: [FontWeightStep]) -> FontWeightStep {
        guard !weights.isEmpty else { return .regular }
        let i = Int((min(max(p, 0), 1) * Double(weights.count - 1)).rounded())
        return weights[min(max(i, 0), weights.count - 1)]
    }

    /// Slider position of `w` (or of the nearest supported weight).
    public static func position(of w: FontWeightStep, in weights: [FontWeightStep]) -> Double {
        guard weights.count > 1 else { return 0 }
        let target = FontSpecimen.nearest(w, in: weights)
        let i = weights.firstIndex(of: target) ?? 0
        return Double(i) / Double(weights.count - 1)
    }
}
