import Foundation
import WhimsyCore

/// Size of a card in points.
public struct CardSize: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public var isEmpty: Bool { !(width > 0 && height > 0) }
}
