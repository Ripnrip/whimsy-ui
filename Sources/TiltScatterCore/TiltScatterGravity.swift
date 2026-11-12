import Foundation

/// Screen-plane gravity for the tray.
///
/// `tilt` is −1…1 on each axis. Zero is the reading pose: gravity points down the
/// screen. Positive `tilt.x` rolls the right edge down, so letters slide right.
/// Positive `tilt.y` tips the top toward the reader, so letters slide up the screen.
/// The magnitude is fixed; only the direction moves. `sin` is ``TiltScatterMath/sin``.
public enum TiltScatterGravity {
    /// Points per second squared, before the pose scales the axes.
    public static let magnitude = 1500.0
    /// Downward pitch, in radians, when the tray is level.
    public static let neutralPitch = 0.70
    /// Radians of roll or pitch at a full ±1 tilt.
    public static let tiltRange = 1.15

    public static func acceleration(tilt: Vec2) -> Vec2 {
        let down = Vec2(0, magnitude * TiltScatterMath.sin(neutralPitch))
        guard tilt.x.isFinite, tilt.y.isFinite else { return down }
        let x = WhimsyMath.clamp(tilt.x, -1, 1)
        let y = WhimsyMath.clamp(tilt.y, -1, 1)
        let roll = x * tiltRange
        let pitch = neutralPitch - y * tiltRange
        return Vec2(
            TiltScatterMath.sin(roll) * magnitude,
            TiltScatterMath.sin(pitch) * magnitude
        )
    }
}

/// Device attitude and a finger in the tray, both turned into the same −1…1 tilt.
public enum TiltScatterMotionMap {
    /// Radians. A phone held up to read sits near here; CoreMotion's pitch is larger
    /// when the top of the phone tips away from the reader.
    public static let neutralPitch = 0.60
    public static let range = 0.55

    /// `pitch` and `roll` are radians from `CMAttitude`.
    /// Roll right (positive) tips the tray right. Pitch above neutral — top tipped
    /// away, bottom downhill — yields a negative `tilt.y`, which strengthens the
    /// downward pull rather than sending letters up the screen.
    public static func tilt(pitch: Double, roll: Double) -> Vec2 {
        guard pitch.isFinite, roll.isFinite, range > 0 else { return .zero }
        return Vec2(
            WhimsyMath.clamp(roll / range, -1, 1),
            WhimsyMath.clamp(-(pitch - neutralPitch) / range, -1, 1)
        )
    }

    /// A finger in a view of `size`. Right of centre tips right. Below centre tips
    /// forward (stronger down-the-screen gravity).
    public static func tilt(fromFinger point: Vec2, in size: Vec2) -> Vec2 {
        guard size.x > 1, size.y > 1, point.x.isFinite, point.y.isFinite else { return .zero }
        let nx = WhimsyMath.clamp((point.x / size.x) * 2 - 1, -1, 1)
        let ny = WhimsyMath.clamp((point.y / size.y) * 2 - 1, -1, 1)
        return Vec2(nx, -ny)
    }
}
