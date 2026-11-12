import Foundation
@testable import TiltScatterCore

extension TiltScatterModel {
    @discardableResult
    mutating func run(_ seconds: Double) -> [TiltScatterEvent] {
        var events: [TiltScatterEvent] = []
        var left = seconds
        while left > 1e-9 {
            let h = min(left, 1.0 / 60)
            events += step(dt: h)
            left -= h
        }
        return events
    }

    var finite: Bool {
        chips.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite && $0.angle.isFinite
                && $0.velocity.x.isFinite && $0.velocity.y.isFinite && $0.spin.isFinite
        }
    }
}

func haptics(_ events: [TiltScatterEvent], _ kind: TiltScatterHaptic) -> Int {
    events.filter {
        if case .haptic(let haptic) = $0 { return haptic == kind }
        return false
    }.count
}
