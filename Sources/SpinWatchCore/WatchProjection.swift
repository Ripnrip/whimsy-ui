import Foundation

/// Fakes a solid watch from flat layers. Each layer lies parallel to the face at depth `z`
/// (towards you is +z) and is rotated about the vertical axis by the yaw: it squashes by
/// cos θ and slides sideways by −z·sin θ. Painting the layers far-to-near gives the solid.
public enum WatchProjection {
    public struct Placement: Equatable, Sendable {
        /// Horizontal shift of the layer's centre, pt.
        public var offsetX: Double
        /// Horizontal scale (negative once the layer faces away, i.e. mirrored).
        public var scaleX: Double
        /// Distance towards the viewer after rotation (larger is nearer).
        public var depth: Double
    }

    /// Rotates the point (x, z) by `yawDegrees` (positive brings the +x side towards you).
    public static func rotate(x: Double, z: Double, yawDegrees: Double) -> (x: Double, z: Double) {
        let t = yawDegrees * .pi / 180
        return (x * cos(t) - z * sin(t), x * sin(t) + z * cos(t))
    }

    /// A face-parallel layer centred at (x, z).
    public static func place(x: Double = 0, z: Double, yawDegrees: Double) -> Placement {
        let r = rotate(x: x, z: z, yawDegrees: yawDegrees)
        return Placement(offsetX: r.x, scaleX: cos(yawDegrees * .pi / 180), depth: r.z)
    }

    /// Indices of `depths` sorted far-to-near (stable for ties).
    public static func paintOrder(_ depths: [Double]) -> [Int] {
        depths.indices.sorted { (depths[$0], $0) < (depths[$1], $1) }
    }

    /// True when the dial side faces you.
    public static func frontVisible(yawDegrees: Double) -> Bool { cos(yawDegrees * .pi / 180) > 0 }

    /// Light from the upper left, in front: unit vector in the (x, z) plane.
    public static let light: (x: Double, z: Double) = (-0.45 / 1.0062, 0.9 / 1.0062)

    /// Lambert brightness 0.35…1 for a surface whose outward normal points along `angle`
    /// (degrees in the x–z plane, 0 = towards you) after `yaw`.
    public static func brightness(normalAngle: Double, yawDegrees: Double) -> Double {
        let a = (normalAngle - yawDegrees) * .pi / 180
        let n = (x: sin(a), z: cos(a))
        let l = (x: light.x, z: light.z), ln = (l.x * l.x + l.z * l.z).squareRoot()
        return 0.35 + 0.65 * max(0, (n.x * l.x + n.z * l.z) / ln)
    }

    /// Brightness of the case band: whichever side (left or right) faces you.
    public static func bandBrightness(yawDegrees: Double) -> Double {
        max(brightness(normalAngle: 90, yawDegrees: yawDegrees) * (sin(yawDegrees * .pi / 180) > 0 ? 1 : 0),
            brightness(normalAngle: -90, yawDegrees: yawDegrees) * (sin(yawDegrees * .pi / 180) < 0 ? 1 : 0),
            0.35)
    }
}
