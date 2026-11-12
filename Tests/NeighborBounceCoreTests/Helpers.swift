import Foundation
@testable import NeighborBounceCore

extension NeighborBounceModel {
    @discardableResult
    mutating func run(_ seconds: Double) -> [NeighborBounceEvent] {
        var out: [NeighborBounceEvent] = []
        let n = Int((seconds / NeighborBounceTuning.substep).rounded())
        for _ in 0..<max(0, n) { out += step(NeighborBounceTuning.substep) }
        return out
    }
}

func isLanded(_ event: NeighborBounceEvent) -> Bool {
    if case .landed = event { return true }
    return false
}

func isLaunched(_ event: NeighborBounceEvent) -> Bool {
    if case .launched = event { return true }
    return false
}
