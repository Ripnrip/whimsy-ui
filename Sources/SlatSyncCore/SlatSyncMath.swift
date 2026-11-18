import Foundation

/// One slat's reed: blur, sideways shift of the light, and a small x-axis tilt.
/// Built from a 32-bit mix of the index so Swift and `webports/slatsync-core.mjs` agree.
public struct SlatOptics: Equatable, Sendable {
    public var index: Int
    public var blur: Double
    public var offsetX: Double
    public var tilt: Double

    public init(index: Int, blur: Double, offsetX: Double, tilt: Double) {
        self.index = index
        self.blur = blur
        self.offsetX = offsetX
        self.tilt = tilt
    }
}

/// Device attitude in radians. Positive roll shifts the light to the right.
/// Positive pitch tips the top of the phone away from you.
public struct SlatDeviceTilt: Equatable, Sendable {
    public var roll: Double
    public var pitch: Double

    public init(roll: Double, pitch: Double) {
        self.roll = roll
        self.pitch = pitch
    }

    public static let zero = SlatDeviceTilt(roll: 0, pitch: 0)
}

/// Extra motion added on top of a slat's reed.
public struct SlatWobble: Equatable, Sendable {
    public var offsetX: Double
    public var tilt: Double

    public init(offsetX: Double, tilt: Double) {
        self.offsetX = offsetX
        self.tilt = tilt
    }

    public static let zero = SlatWobble(offsetX: 0, tilt: 0)
}

public struct SlatFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Everything one slat needs to draw. `tilt` is degrees, `spread` is 0…1 of the slat width.
public struct SlatBand: Equatable, Sendable {
    public var index: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var blur: Double
    public var offsetX: Double
    public var tilt: Double
    public var spread: Double
    public var red: Double
    public var green: Double
    public var blue: Double
    public var edge: Double
    public var opacity: Double

    public init(index: Int, x: Double, y: Double, width: Double, height: Double,
                blur: Double, offsetX: Double, tilt: Double, spread: Double,
                red: Double, green: Double, blue: Double, edge: Double, opacity: Double) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.blur = blur
        self.offsetX = offsetX
        self.tilt = tilt
        self.spread = spread
        self.red = red
        self.green = green
        self.blue = blue
        self.edge = edge
        self.opacity = opacity
    }
}

/// The hero at one progress value.
public struct SlatSyncScene: Equatable, Sendable {
    public var progress: Double
    public var percent: Int
    public var label: SlatSyncLabel
    public var voiceOver: String
    public var opacity: Double
    public var bands: [SlatBand]

    public init(progress: Double, percent: Int, label: SlatSyncLabel, voiceOver: String,
                opacity: Double, bands: [SlatBand]) {
        self.progress = progress
        self.percent = percent
        self.label = label
        self.voiceOver = voiceOver
        self.opacity = opacity
        self.bands = bands
    }

    /// `progress` is clamped to 0…1 for the picture. Non-finite progress is 0.
    /// Reduce Motion fades the finished aurora in (opacity follows progress, every slat
    /// already at full spread) and adds no wobble. Full motion grows the spread and
    /// keeps the aurora opaque.
    public static func make(progress: Double, roll: Double = 0, pitch: Double = 0,
                            reduceMotion: Bool = false) -> SlatSyncScene {
        let unit = SlatSyncMath.unitProgress(progress)
        let pct = SlatSyncMath.percent(for: progress)
        let label = SlatSyncMath.label(for: pct)
        let reveal = reduceMotion ? 1.0 : unit
        let opacity = reduceMotion ? unit : 1.0
        let bands = (0..<SlatSyncTuning.slatCount).map { index in
            let frame = SlatSyncMath.frame(index: index)
            let optics = SlatSyncMath.optics(index: index)
            let wobble = SlatSyncMath.wobble(index: index, roll: roll, pitch: pitch, reduceMotion: reduceMotion)
            let spread = SlatSyncMath.spread(index: index, progress: reveal)
            let color = SlatSyncMath.color(index: index)
            let edge = SlatSyncTuning.edgeBase + SlatSyncTuning.edgeGain * spread * opacity
            return SlatBand(
                index: index, x: frame.x, y: frame.y, width: frame.width, height: frame.height,
                blur: optics.blur, offsetX: optics.offsetX + wobble.offsetX, tilt: optics.tilt + wobble.tilt,
                spread: spread, red: color.red, green: color.green, blue: color.blue,
                edge: edge, opacity: opacity
            )
        }
        return SlatSyncScene(
            progress: unit, percent: pct, label: label,
            voiceOver: SlatSyncMath.voiceOver(percent: pct),
            opacity: opacity, bands: bands
        )
    }
}

/// Remembers the last progress and counts crossings into 100%.
public struct SlatSyncMonitor: Equatable, Sendable {
    public private(set) var progress: Double
    public private(set) var hapticCount: Int

    public init(progress: Double = 0) {
        self.progress = SlatSyncMath.unitProgress(progress)
        hapticCount = 0
    }

    /// Moves to `next`. Returns whether this call crossed into a displayed 100%.
    /// A non-finite value is ignored. Holding at 100% does not fire again.
    /// Dropping below 100% re-arms the next crossing.
    @discardableResult
    public mutating func setProgress(_ next: Double) -> Bool {
        guard next.isFinite else { return false }
        let fired = SlatSyncMath.crossedHundred(from: progress, to: next)
        progress = SlatSyncMath.unitProgress(next)
        if fired { hapticCount += 1 }
        return fired
    }
}

public enum SlatSyncMath {
    /// 0…1. Non-finite input is 0.
    public static func unitProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    /// Nearest percent, half away from zero. 0.995 displays as 100, 0.994 as 99.
    /// A tiny epsilon keeps binary fractions such as 0.995 on the right side of the tie.
    public static func percent(for progress: Double) -> Int {
        guard progress.isFinite else { return 0 }
        let scaled = unitProgress(progress) * 100 + 1e-8
        let rounded = scaled.rounded(.toNearestOrAwayFromZero)
        return Int(min(max(rounded, 0), 100))
    }

    public static func label(for percent: Int) -> SlatSyncLabel {
        percent >= 100 ? .synced : .syncing
    }

    /// What VoiceOver should say. "Syncing, 42 percent" or "All synced".
    public static func voiceOver(percent: Int) -> String {
        percent >= 100 ? SlatSyncTuning.synced : "Syncing, \(percent) percent"
    }

    /// True when the displayed percent moves from below 100 to 100.
    public static func crossedHundred(from previous: Double, to next: Double) -> Bool {
        percent(for: previous) < 100 && percent(for: next) >= 100
    }

    public static func frame(index: Int) -> SlatFrame {
        let y = SlatSyncTuning.stackTop + Double(index) * (SlatSyncTuning.slatHeight + SlatSyncTuning.slatGap)
        let x = (SlatSyncTuning.canvasWidth - SlatSyncTuning.slatWidth) / 2
        return SlatFrame(x: x, y: y, width: SlatSyncTuning.slatWidth, height: SlatSyncTuning.slatHeight)
    }

    /// Reed for slat `index`. Outside 0…10 the slat is dark and flat.
    public static func optics(index: Int) -> SlatOptics {
        guard (0..<SlatSyncTuning.slatCount).contains(index) else {
            return SlatOptics(index: index, blur: 0, offsetX: 0, tilt: 0)
        }
        let dist = abs(Double(index) - 5) / 5
        let u = unit(index: index, salt: 1)
        let v = unit(index: index, salt: 2)
        let w = unit(index: index, salt: 3)
        let signV = v < 0.5 ? -1.0 : 1.0
        let signW = w < 0.5 ? -1.0 : 1.0
        // The distance term dominates the jitter, so the centre stays the sharpest slat.
        let blur = 3.2 + dist * 14 + (u - 0.5) * 1.2
        let offset = signV * (4 + dist * 16) * (0.65 + 0.35 * v)
        let tilt = signW * (0.35 + dist * 4.4) * (0.7 + 0.3 * w)
        return SlatOptics(index: index, blur: blur, offsetX: offset, tilt: tilt)
    }

    /// 0…1 width of the aurora inside this slat.
    /// At rest only the middle five are lit, and only as a small core. At 1 every slat is nearly full.
    public static func spread(index: Int, progress: Double) -> Double {
        guard (0..<SlatSyncTuning.slatCount).contains(index) else { return 0 }
        guard progress.isFinite else { return 0 }
        let p = min(max(progress, 0), 1)
        let dist = abs(Double(index) - 5)
        let reach = SlatSyncTuning.reachStart + (SlatSyncTuning.reachEnd - SlatSyncTuning.reachStart) * p
        let gate = smoothstep(reach, reach - SlatSyncTuning.reachFeather, dist)
        let base = SlatSyncTuning.spreadFloor + (SlatSyncTuning.spreadCeil - SlatSyncTuning.spreadFloor) * p
        let taper = 1 - 0.10 * (dist / 5) * (1 - 0.65 * p)
        return min(max(base * taper * gate, 0), 1)
    }

    /// Cobalt at the top slat, teal through the middle, lime at the bottom.
    public static func color(index: Int) -> SlatRGB {
        guard (0..<SlatSyncTuning.slatCount).contains(index) else { return SlatSyncTuning.cobalt }
        if index == 0 { return SlatSyncTuning.cobalt }
        if index == SlatSyncTuning.slatCount - 1 { return SlatSyncTuning.lime }
        let t = Double(index) / Double(SlatSyncTuning.slatCount - 1)
        if t <= SlatSyncTuning.tealStop {
            return SlatRGB.lerp(SlatSyncTuning.cobalt, SlatSyncTuning.teal, t / SlatSyncTuning.tealStop)
        }
        return SlatRGB.lerp(SlatSyncTuning.teal, SlatSyncTuning.lime, (t - SlatSyncTuning.tealStop) / (1 - SlatSyncTuning.tealStop))
    }

    /// Roll slides the light sideways, more at the ends. Pitch bows the stack so the top and
    /// bottom tip opposite ways. Reduce Motion, or a non-finite attitude, returns zero.
    public static func wobble(index: Int, roll: Double, pitch: Double, reduceMotion: Bool) -> SlatWobble {
        guard !reduceMotion, roll.isFinite, pitch.isFinite else { return .zero }
        guard (0..<SlatSyncTuning.slatCount).contains(index) else { return .zero }
        let clampedRoll = min(max(roll, -SlatSyncTuning.maxAttitude), SlatSyncTuning.maxAttitude)
        let clampedPitch = min(max(pitch, -SlatSyncTuning.maxAttitude), SlatSyncTuning.maxAttitude)
        let lever = (Double(index) - 5) / 5
        let depth = 0.40 + 0.60 * abs(lever)
        let offsetX = clampedRoll * SlatSyncTuning.rollTravel * depth
        let tilt = -clampedPitch * (180 / .pi) * SlatSyncTuning.pitchBow * lever
        return SlatWobble(offsetX: offsetX, tilt: tilt)
    }

    /// Progress of the scripted demo. 0 until `demoDelay`, then an ease-in-out cubic over `demoRun`.
    public static func demoProgress(at time: Double) -> Double {
        guard time.isFinite else { return 0 }
        let t = max(time, 0)
        if t <= SlatSyncTuning.demoDelay { return 0 }
        let u = min(1, (t - SlatSyncTuning.demoDelay) / SlatSyncTuning.demoRun)
        return easeInOutCubic(u)
    }

    /// Algebraic ease, multiplication only, so the web port matches bit for bit.
    public static func easeInOutCubic(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        if t < 0.5 { return 4 * t * t * t }
        let u = 2 - 2 * t
        return 1 - (u * u * u) / 2
    }

    /// 0 when `x` is at `a`, 1 when `x` is at `b`. `a` may be greater than `b`.
    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t: Double
        if a == b {
            t = x < a ? 0 : 1
        } else {
            t = min(max((x - a) / (b - a), 0), 1)
        }
        return t * t * (3 - 2 * t)
    }

    /// Unit value in 0…1 from a 32-bit mix. The steps match `slatsync-core.mjs`.
    public static func unit(index: Int, salt: Int) -> Double {
        var z = UInt32(truncatingIfNeeded: index) &* 0x9E37_79B1
        z &+= UInt32(truncatingIfNeeded: salt) &* 0x85EB_CA77
        z &+= 0xA11C_E5D3
        z ^= z >> 16
        z &*= 0x7FEB_352D
        z ^= z >> 15
        z &*= 0x846C_A68B
        z ^= z >> 16
        return Double(z) / 4294967295.0
    }
}
