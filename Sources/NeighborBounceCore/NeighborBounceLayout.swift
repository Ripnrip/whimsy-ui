import Foundation

/// One segment of a neighbor-bounce picker. Pure data, so the control and the web preview share it.
public struct NeighborTick: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(id: String, title: String, red: Double, green: Double, blue: Double) {
        self.id = id
        self.title = title
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Six short labels. The demo and the empty-list default.
    public static let demo: [NeighborTick] = [
        NeighborTick(id: "ink", title: "Ink", red: 0.18, green: 0.20, blue: 0.28),
        NeighborTick(id: "sage", title: "Sage", red: 0.35, green: 0.52, blue: 0.40),
        NeighborTick(id: "clay", title: "Clay", red: 0.72, green: 0.40, blue: 0.30),
        NeighborTick(id: "gold", title: "Gold", red: 0.78, green: 0.58, blue: 0.22),
        NeighborTick(id: "plum", title: "Plum", red: 0.48, green: 0.28, blue: 0.48),
        NeighborTick(id: "tide", title: "Tide", red: 0.22, green: 0.42, blue: 0.55),
    ]

    /// A legal row: 5…7 ticks. Extras are dropped. A shorter list is padded with numbered ticks
    /// coloured from ``demo``. An empty list is the demo.
    public static func fitted(_ ticks: [NeighborTick]) -> [NeighborTick] {
        if ticks.isEmpty { return demo }
        let capped = Array(ticks.prefix(NeighborBounceLayout.maxTicks))
        if capped.count >= NeighborBounceLayout.minTicks { return capped }
        var out = capped
        var n = out.count
        while out.count < NeighborBounceLayout.minTicks {
            let swatch = demo[n % demo.count]
            out.append(NeighborTick(
                id: "tick-\(n + 1)",
                title: "\(n + 1)",
                red: swatch.red,
                green: swatch.green,
                blue: swatch.blue
            ))
            n += 1
        }
        return out
    }
}

/// Chrome colours shared with the canvas preview. Components are 0…1.
public enum NeighborBouncePalette {
    public static let paperR = 0.965, paperG = 0.945, paperB = 0.910
    public static let trackR = 0.898, trackG = 0.863, trackB = 0.784
    public static let inkR = 0.165, inkG = 0.145, inkB = 0.125
    public static let tickR = 0.995, tickG = 0.988, tickB = 0.976
}

/// Geometry of the row. Counts outside 5…7 are clamped. The row is centred in the canvas.
public enum NeighborBounceLayout {
    public static let minTicks = 5
    public static let maxTicks = 7
    public static let defaultTicks = 6
    public static let canvasWidth = 404.0
    public static let canvasHeight = 196.0
    public static let tickDiameter = 46.0
    public static let gap = 10.0
    public static let restY = 128.0
    public static let trackWidth = 376.0
    public static let trackHeight = 78.0
    public static let indicatorWidth = 74.0
    public static let indicatorHeight = 54.0

    public static func clampedCount(_ count: Int) -> Int {
        min(max(count, minTicks), maxTicks)
    }

    public static func rowWidth(count: Int) -> Double {
        let n = Double(clampedCount(count))
        return n * tickDiameter + (n - 1) * gap
    }

    public static func originX(count: Int) -> Double {
        (canvasWidth - rowWidth(count: count)) / 2
    }

    /// Resting centre of tick `index`. Out-of-range indexes clamp. Screen y grows downward.
    public static func restCenter(index: Int, count: Int) -> Vec2 {
        let n = clampedCount(count)
        let i = min(max(index, 0), n - 1)
        let x = originX(count: n) + tickDiameter / 2 + Double(i) * (tickDiameter + gap)
        return Vec2(x, restY)
    }

    /// Nearest tick by resting x. A tie on the midpoint belongs to the lower index.
    public static func index(atX x: Double, count: Int) -> Int {
        let n = clampedCount(count)
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        if !x.isFinite { return best }
        for i in 0..<n {
            let d = abs(x - restCenter(index: i, count: n).x)
            if d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }
}

/// Springs, kick, stagger and the landing haptic. The web preview copies these literals.
public enum NeighborBounceTuning {
    /// Fixed integrator step. `1/60` is four of these.
    public static let substep = 1.0 / 240.0
    /// A stalled frame is clamped to 24 substeps instead of exploding.
    public static let maxFrame = 24.0 * substep
    /// Substeps of delay per step of distance from the selected tick.
    public static let staggerSteps = 12
    public static var stagger: Double { Double(staggerSteps) * substep }
    /// Speed added to a distance-1 neighbour, before the 3-4-5 split into x and y.
    public static let kickSpeed = 1200.0
    /// Each further step of distance multiplies the kick by this (5/8).
    public static let decay = 0.625
    public static let offsetStiffness = 100.0
    public static let offsetDamping = 0.5
    public static let scaleStiffness = 324.0
    public static let scaleDamping = 0.75
    public static let selectedScale = 1.125
    public static let indicatorStiffness = 196.0
    public static let indicatorDamping = 0.75
    /// A tick is "in the air" once its offset y is above this (screen y is down, so the test is `< -band`).
    public static let landBand = 4.0
    /// Downward speed required to count as a landing, so a tiny return does not tick.
    public static let landSpeed = 48.0
    /// Minimum time between landing haptics. Wider than the wave's landing gaps, so a burst collapses.
    public static var hapticGap: Double { 18.0 * substep }
    public static let stretchDivisor = 1600.0
    public static let stretchLimit = 0.125
    public static let stretchLateral = 0.5
}

/// The velocity a selection adds to one neighbour. Distance 0, or a zero sign, is no kick.
public enum NeighborBounceWave {
    public static func impulse(distance: Int, sign: Double) -> Vec2 {
        guard distance > 0, sign.isFinite, sign != 0 else { return .zero }
        var speed = NeighborBounceTuning.kickSpeed
        var i = 1
        while i < distance {
            speed *= NeighborBounceTuning.decay
            i += 1
        }
        let s = sign > 0 ? 1.0 : -1.0
        // Multiply before dividing so these speeds stay on exact binary values (1200 is divisible by 5).
        return Vec2(s * speed * 3.0 / 5.0, -speed * 4.0 / 5.0)
    }
}

public enum NeighborBounceMath {
    /// IEEE-754 bits, lowercase hex, −0 folded to +0. The canvas port prints the same text.
    public static func hex(_ d: Double) -> String {
        var x = d
        if x == 0 { x = 0 }
        let raw = String(x.bitPattern, radix: 16)
        if raw.count >= 16 { return raw }
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}

/// Where a tick is drawn: resting centre plus the spring offset, with a velocity squash.
public struct NeighborBouncePose: Equatable, Sendable {
    public var center: Vec2
    public var scaleX: Double
    public var scaleY: Double
    public var lift: Double
}
