import Foundation

public enum GlassLightID: String, Equatable, Sendable {
    case amber, red
}

/// One pose of the glass: the shape, the two lights, and how much of each face shows.
public struct GlassMorphFrame: Equatable, Sendable {
    public var center: Vec2
    public var width: Double
    public var height: Double
    public var cornerRadius: Double
    /// Radians, y-down. Negative leans the top to the left.
    public var tilt: Double

    public init(center: Vec2, width: Double, height: Double, cornerRadius: Double, tilt: Double) {
        self.center = center
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.tilt = tilt
    }
}

public struct GlassLight: Equatable, Sendable {
    public var center: Vec2
    public var radius: Double
    public var blur: Double

    public init(center: Vec2, radius: Double, blur: Double) {
        self.center = center
        self.radius = radius
        self.blur = blur
    }
}

public enum GlassMorphPhase: String, Equatable, Sendable {
    case card, morphing, pill, unfolding
}

/// Pure geometry. `progress` 0 is the card and 1 is the pill. Values outside 0…1
/// are the spring's overshoot: the shape follows them, the tilt and the blurs clamp.
public enum GlassMorphLayout {
    public static func frame(progress: Double) -> GlassMorphFrame {
        let t = progress.isFinite ? progress : 0
        let u = WhimsyMath.clamp01(t)
        return GlassMorphFrame(
            center: GlassMorphTuning.stageCenter,
            width: max(1, WhimsyMath.lerp(GlassMorphTuning.cardWidth, GlassMorphTuning.pillWidth, t)),
            height: max(1, WhimsyMath.lerp(GlassMorphTuning.cardHeight, GlassMorphTuning.pillHeight, t)),
            cornerRadius: max(0, WhimsyMath.lerp(GlassMorphTuning.cardCorner, GlassMorphTuning.pillCorner, t)),
            tilt: WhimsyMath.lerp(GlassMorphTuning.cardTilt, 0, u)
        )
    }

    public static func light(_ id: GlassLightID, progress: Double) -> GlassLight {
        let t = progress.isFinite ? progress : 0
        // The lights travel the segment and stop on the dots. The glass frame is
        // what overshoots; a light should not fly past the mark.
        let u = WhimsyMath.clamp01(t)
        switch id {
        case .amber:
            return GlassLight(
                center: Vec2.lerp(GlassMorphTuning.amberRest, GlassMorphTuning.amberLogo, u),
                radius: max(0, WhimsyMath.lerp(GlassMorphTuning.amberRestRadius, GlassMorphTuning.amberLogoRadius, u)),
                blur: max(0, WhimsyMath.lerp(GlassMorphTuning.amberRestBlur, GlassMorphTuning.logoBlur, u))
            )
        case .red:
            return GlassLight(
                center: Vec2.lerp(GlassMorphTuning.redRest, GlassMorphTuning.redLogo, u),
                radius: max(0, WhimsyMath.lerp(GlassMorphTuning.redRestRadius, GlassMorphTuning.redLogoRadius, u)),
                blur: max(0, WhimsyMath.lerp(GlassMorphTuning.redRestBlur, GlassMorphTuning.logoBlur, u))
            )
        }
    }

    /// Flip angle at `age` seconds into the unfold. 0 at the start, π at the end.
    /// Algebraic cubic, so the web port can replay it without `pow`.
    public static func flipAngle(at age: Double) -> Double {
        guard age.isFinite else { return 0 }
        let u = WhimsyMath.clamp01(age / GlassMorphTuning.unfoldDuration)
        return Double.pi * easeInOutCubic(u)
    }

    public static func easeInOutCubic(_ t: Double) -> Double {
        let t = WhimsyMath.clamp01(t)
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - (u * u * u) / 2
    }

    public static func cardContentOpacity(phase: GlassMorphPhase, progress: Double, flip: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 - WhimsyMath.clamp01(progress) }
        switch phase {
        case .card: return 1
        case .morphing: return 1 - WhimsyMath.smoothstep(0, 0.22, WhimsyMath.clamp01(progress))
        case .pill: return 0
        case .unfolding: return flip >= Double.pi / 2 ? 1 : 0
        }
    }

    public static func dotOpacity(phase: GlassMorphPhase, progress: Double, flip: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return WhimsyMath.clamp01(progress) }
        switch phase {
        case .card: return 0
        case .morphing: return WhimsyMath.smoothstep(0.55, 0.95, WhimsyMath.clamp01(progress))
        case .pill: return 1
        case .unfolding: return flip >= Double.pi / 2 ? 0 : 1
        }
    }

    public static func glowOpacity(phase: GlassMorphPhase, progress: Double, flip: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 - WhimsyMath.clamp01(progress) }
        switch phase {
        case .card: return 1
        case .morphing: return 1 - WhimsyMath.smoothstep(0.25, 0.8, WhimsyMath.clamp01(progress))
        case .pill: return 0
        case .unfolding: return flip >= Double.pi / 2 ? WhimsyMath.smoothstep(0.25, 0.8, 1 - WhimsyMath.clamp01(progress)) : 0
        }
    }

    /// 1 when the half-turn is edge-on, 0 at either face and whenever the flip is off.
    public static func edgeGlow(phase: GlassMorphPhase, flip: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, phase == .unfolding else { return 0 }
        let d = abs(flip - Double.pi / 2)
        return WhimsyMath.clamp01(1 - d / GlassMorphTuning.edgeWidth)
    }

    /// Clockwise-positive rotation in y-down space, matching SwiftUI's `rotationEffect`.
    public static func rotate(_ point: Vec2, by angle: Double) -> Vec2 {
        let c = cos(angle)
        let s = sin(angle)
        return Vec2(point.x * c - point.y * s, point.x * s + point.y * c)
    }

    public static func worldPoint(_ local: Vec2, center: Vec2, tilt: Double) -> Vec2 {
        center + rotate(local, by: tilt)
    }

    public static func localPoint(_ world: Vec2, center: Vec2, tilt: Double) -> Vec2 {
        rotate(world - center, by: -tilt)
    }

    /// What `rotation3DEffect` should use. Past the edge, the angle is shifted by −π
    /// so the card face comes back upright instead of mirrored.
    public static func displayFlip(_ flip: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        if flip <= Double.pi / 2 { return flip }
        return flip - Double.pi
    }
}
