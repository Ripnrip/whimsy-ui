import Foundation
@testable import HoldToFanCore

extension HoldToFanModel {
    @discardableResult
    mutating func run(_ seconds: Double, fps: Double = 60) -> [HoldToFanEvent] {
        var out: [HoldToFanEvent] = []
        let n = Int((seconds * fps).rounded())
        for _ in 0..<n { out += step(1 / fps) }
        return out
    }

    /// Hold past the arm threshold and wait until open (or `cap` seconds).
    @discardableResult
    mutating func armAndOpen(cap: Double = 1.5) -> [HoldToFanEvent] {
        var out: [HoldToFanEvent] = pressBegan()
        var t = 0.0
        while phase != .open && t < cap {
            out += step(1.0 / 60); t += 1.0 / 60
        }
        return out
    }
}

func onlyPhases(_ events: [HoldToFanEvent]) -> [HoldToFanEvent] {
    events.filter {
        switch $0 {
        case .armed, .opened, .selected, .cancelled, .seated, .pulsed: return true
        }
    }
}
