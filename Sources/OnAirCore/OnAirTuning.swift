import Foundation

/// Layout, spring, dim, breath and timer constants shared with `webports/onair-core.mjs`.
/// Change both together. The pill geometry is part of the model because drag progress is
/// measured in these points.
public enum OnAirTuning {
    public static let sceneWidth = 390.0
    public static let sceneHeight = 844.0

    public static let pillWidth = 232.0
    public static let pillHeight = 88.0
    public static let pillX = (sceneWidth - pillWidth) / 2
    public static let pillY = 456.0

    public static let knobDiameter = 68.0
    public static let knobInset = 10.0
    /// How far past the pill a finger still grabs the knob, in points.
    public static let pillGrabPad = 28.0

    public static let commitThreshold = 0.5
    /// A release that moved less than this, horizontally, is a tap and toggles.
    public static let tapSlop = 8.0

    /// One spring drives the throw. Underdamped so the knob kisses past the stop, then sits.
    public static let stiffness = 260.0
    public static let dampingRatio = 0.72
    public static let settleTolerance = 0.001

    /// Reduce Motion crossfade. No spring, no breath.
    public static let reduceDuration = 0.28

    /// Breathing glow while live. A full cycle, and how far the lamp dips at the trough.
    public static let breathPeriod = 2.6
    public static let breathDepth = 0.28

    /// Colour-multiply of the room at full throw. Near-black, not a hard cut to zero.
    public static let dimFloor = 0.055

    public static let onAirLabel = "ON AIR"
    public static let wordmark = "Murmur"
    public static let subtitle = "EVENING SHOW"

    public static let wordmarkY = 108.0
    public static let subtitleY = 142.0
    public static let onAirY = 586.0
    public static let timerY = 632.0
    public static let meterY = 678.0
    public static let meterMaxHeight = 36.0
    public static let meterBarWidth = 7.0
    public static let meterGap = 6.0
    public static let meterCount = 7

    public static var travel: Double { pillWidth - knobDiameter - 2 * knobInset }

    public static func knobCenter(progress: Double) -> (x: Double, y: Double) {
        let visual = min(max(progress, -0.05), 1.05)
        let x = pillX + knobInset + knobDiameter / 2 + travel * visual
        let y = pillY + pillHeight / 2
        return (x, y)
    }

    /// Knob progress for a finger at `x` in scene points. Clamped to the track.
    public static func progress(forSceneX x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let start = pillX + knobInset + knobDiameter / 2
        return WhimsyMath.clamp01((x - start) / travel)
    }

    public static func sceneX(forProgress progress: Double) -> Double {
        let start = pillX + knobInset + knobDiameter / 2
        return start + travel * WhimsyMath.clamp01(progress)
    }

    public static func pillContains(y: Double) -> Bool {
        guard y.isFinite else { return false }
        return y >= pillY - pillGrabPad && y <= pillY + pillHeight + pillGrabPad
    }

    /// 0 when the room is bright, 1 when the throw has dimmed it.
    public static func dimAmount(progress: Double) -> Double {
        WhimsyMath.smoothstep(0.05, 0.95, WhimsyMath.clamp01(progress))
    }

    /// White-multiply applied to the room. 1 off, `dimFloor` at the end of the throw.
    public static func backgroundMultiply(progress: Double) -> Double {
        WhimsyMath.lerp(1, dimFloor, dimAmount(progress: progress))
    }

    /// 1 at the peaks, `1 - breathDepth` at the troughs. Reduce Motion and t ≤ 0 stay at 1.
    public static func breath(at time: Double, reduceMotion: Bool) -> Double {
        if reduceMotion || !time.isFinite || time <= 0 { return 1 }
        let wave = OnAirMath.cos(OnAirMath.twoPi * time / breathPeriod)
        return 1 - breathDepth * (1 - wave) * 0.5
    }

    /// Lamp brightness. The bloom, the red lens and the breath all read this one number.
    /// Breath only runs while the switch is committed on, so a fade-out does not pulse.
    public static func glow(progress: Double, elapsed: Double, live: Bool, reduceMotion: Bool) -> Double {
        let base = WhimsyMath.smoothstep(0.38, 1, WhimsyMath.clamp01(progress))
        guard live, !reduceMotion else { return base }
        return base * breath(at: elapsed, reduceMotion: false)
    }

    /// Opacity of the ON AIR label, the timer and the meter. They arrive late in the throw.
    public static func chromeOpacity(progress: Double) -> Double {
        WhimsyMath.smoothstep(0.58, 0.94, WhimsyMath.clamp01(progress))
    }

    /// Seven meter bars in 0.16…1, or a still pattern when motion is reduced.
    public static func meterLevels(at time: Double, reduceMotion: Bool) -> [Double] {
        (0..<meterCount).map { index in
            if reduceMotion || !time.isFinite {
                return 0.34 + 0.08 * Double(index % 4)
            }
            let phase = time * (1.7 + 0.31 * Double(index)) + 0.55 * Double(index)
            let wave = 0.5 + 0.5 * OnAirMath.sin(phase)
            return 0.16 + 0.84 * wave
        }
    }
}

/// `mm:ss` for the on-air timer. Truncates toward zero. Anything unusable is `00:00`.
/// Minutes stop at 99 so the label under the pill cannot grow a third digit.
public enum OnAirClock {
    public static let maxMinutes = 99

    public static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let cap = maxMinutes * 60 + 59
        let whole = min(Int(seconds.rounded(.down)), cap)
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}
