import Foundation
import WhimsyCore

/// Damped spring on a 2D point, as in the article: `c = 2·√k·ζ`, semi-implicit Euler.
public struct Spring2D: Equatable, Sendable {
    public var position: Vec2
    public var velocity: Vec2 = .zero
    public init(_ position: Vec2 = .zero) { self.position = position }

    public mutating func step(toward target: Vec2, dt: Double, stiffness k: Double, damping ratio: Double) {
        let c = 2 * k.squareRoot() * ratio
        let a = (target - position) * k - velocity * c
        velocity = velocity + a * dt
        position = position + velocity * dt
    }
}
