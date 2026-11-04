import Foundation
@testable import StarJarCore

extension StarJarModel {
    @discardableResult
    mutating func run(_ seconds: Double, fps: Double = 60) -> [StarJarEvent] {
        var out: [StarJarEvent] = []
        let n = Int((seconds * fps).rounded())
        for _ in 0..<n { out += step(1 / fps) }
        return out
    }
    var meanY: Double { stars.map(\.y).reduce(0, +) / Double(stars.count) }
    var fastest: Double { stars.map(\.speed).max() ?? 0 }
    /// Largest (distance + radius) over stars; ≤ -wall + tiny means every star sits inside the glass.
    var worstContainment: Double { stars.map { StarJarGeometry.distance($0.x, $0.y) + $0.radius }.max() ?? 0 }
    var allInside: Bool { worstContainment <= -StarJarGeometry.wall + 0.5 }
}

func brushTimes(_ events: [StarJarEvent]) -> Int { events.filter { if case .brush = $0 { return true }; return false }.count }
func phaseEvents(_ events: [StarJarEvent]) -> [StarJarEvent] { events.filter { if case .brush = $0 { return false }; return true } }

/// Puts a model in the awake phase, fully woken.
func awakeModel(count: Int = 40, seed: UInt32 = StarJarModel.defaultSeed, reduce: Bool = false) -> StarJarModel {
    var m = StarJarModel(starCount: count, seed: seed, reduceMotion: reduce)
    _ = m.wakeUp()
    m.run(1)
    return m
}

/// Swirls the finger in a circle inside the body for a number of seconds.
func swirl(_ m: inout StarJarModel, seconds: Double, radius: Double = 50) -> [StarJarEvent] {
    var out: [StarJarEvent] = []
    let c = StarJarGeometry.bodyCenter
    m.touchBegan(x: c.x + radius, y: c.y)
    let n = Int(seconds * 60)
    for k in 0..<n {
        let a = Double(k) * 0.12
        m.touchMoved(x: c.x + radius * cos(a), y: c.y + radius * sin(a), at: m.time)
        out += m.step(1.0 / 60)
    }
    m.touchEnded()
    return out
}
