import Foundation

/// Everything the view needs to draw one row at one moment.
public struct OctoRowFrame: Equatable, Sendable {
    public var index: Int
    public var phase: OctoPhase
    /// 0…1: the circle fills and the checkmark draws in (also drives the strike-through).
    public var check: Double
    public var swell: Double
    public var grab: Double
    /// 0…1 progress of the pull.
    public var pull: Double
    /// Collapse progress; overshoots 1 a little on the spring so the rows below bounce.
    public var collapse: Double
    /// 0…1 reappearance after a reset.
    public var restore: Double
    public var offsetY: Double
    /// Volume-preserving squash and stretch: `scaleX * scaleY == 1`.
    public var scaleX: Double
    public var scaleY: Double
    public var opacity: Double
    /// The height the row's slot takes in the list (negative only during the spring's overshoot).
    public var slotHeight: Double
    /// Top of the slot in list coordinates.
    public var top: Double
    public var blob: OctoBlob?
    public var showsInk: Bool

    /// Row height scale while it collapses out.
    public var heightScale: Double { WhimsyMath.clamp01(restore - collapse) }
}
