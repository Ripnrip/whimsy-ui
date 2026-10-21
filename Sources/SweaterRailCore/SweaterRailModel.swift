import Foundation

/// Everything the rail animates: each garment's hook position and scale on springs, its swing
/// on a pendulum driven by the hook's acceleration, and which garment the finger is over.
public struct SweaterRailModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        public var slotWidth = 62.0
        public var falloff = DockFalloff()
        /// Hook position spring: lively, so a spread kicks the pendulums.
        public var positionStiffness = 260.0
        public var positionDamping = 0.72
        /// Magnification spring.
        public var scaleStiffness = 300.0
        public var scaleDamping = 0.7
        public var pendulumLength = 110.0
        public var gravity = 5_000.0
        public var swingDamping = 3.2
        public var maxSwing = 0.45
        public init() {}
    }

    public struct Garment: Equatable, Sendable {
        public var x: WhimsySpring
        public var scale: WhimsySpring
        public var emphasis: WhimsySpring
        public var swing: Pendulum
    }

    public private(set) var layout: RailLayout
    public private(set) var garments: [Garment]
    public let tuning: Tuning
    /// The finger's x on the rail, or nil when it's away.
    public private(set) var fingerX: Double?
    /// With Reduce Motion: no swing, critically damped springs.
    public var reduceMotion = false {
        didSet {
            for i in garments.indices {
                garments[i].x.dampingRatio = reduceMotion ? 1 : tuning.positionDamping
                garments[i].scale.dampingRatio = reduceMotion ? 1 : tuning.scaleDamping
                if reduceMotion { garments[i].swing.angle = 0; garments[i].swing.angularVelocity = 0 }
            }
        }
    }

    public init(count: Int, railCenter: Double = 0, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        layout = RailLayout(count: count, slotWidth: tuning.slotWidth, railCenter: railCenter, falloff: tuning.falloff)
        garments = layout.baseCenters.map { x in
            Garment(x: WhimsySpring(value: x, stiffness: tuning.positionStiffness, dampingRatio: tuning.positionDamping),
                    scale: WhimsySpring(value: 1, stiffness: tuning.scaleStiffness, dampingRatio: tuning.scaleDamping),
                    emphasis: WhimsySpring(value: 0, stiffness: tuning.scaleStiffness, dampingRatio: 1),
                    swing: Pendulum(length: tuning.pendulumLength, gravity: tuning.gravity,
                                    damping: tuning.swingDamping, maxAngle: tuning.maxSwing))
        }
    }

    public var count: Int { garments.count }

    public mutating func setFinger(_ x: Double?) {
        if let x, !x.isFinite { return }
        fingerX = x
    }

    /// Moves the rail (e.g. after a size change) without animating.
    public mutating func setRailCenter(_ center: Double) {
        guard center.isFinite, center != layout.railCenter else { return }
        let shift = center - layout.railCenter
        layout.railCenter = center
        for i in garments.indices { garments[i].x.value += shift }
    }

    public var hoveredIndex: Int? { layout.hoveredIndex(fingerX: fingerX) }
    public var targets: [RailSlot] { layout.slots(fingerX: fingerX) }

    public mutating func step(_ dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        let goal = targets
        var remaining = min(dt, WhimsySpring.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, WhimsySpring.maxSubstep)
            for i in garments.indices {
                let v0 = garments[i].x.velocity
                garments[i].x.substep(toward: goal[i].centerX, h: h)
                garments[i].scale.substep(toward: goal[i].scale, h: h)
                garments[i].emphasis.substep(toward: goal[i].emphasis, h: h)
                if !reduceMotion {
                    garments[i].swing.substep(pivotAcceleration: (garments[i].x.velocity - v0) / h, h: h)
                }
            }
            remaining -= h
        }
    }

    /// Hook x, scale, swing (degrees, positive = hem to the right) and emphasis of garment `i`.
    public func pose(_ i: Int) -> (x: Double, scale: Double, swingDegrees: Double, emphasis: Double) {
        let g = garments[i]
        return (g.x.value, max(g.scale.value, 0.1), g.swing.angle * 180 / .pi, WhimsyMath.clamp01(g.emphasis.value))
    }

    public var isSettled: Bool {
        let goal = targets
        return garments.indices.allSatisfy { i in
            garments[i].x.isSettled(at: goal[i].centerX, tolerance: 0.05)
                && garments[i].scale.isSettled(at: goal[i].scale, tolerance: 1e-3)
                && garments[i].emphasis.isSettled(at: goal[i].emphasis, tolerance: 1e-3)
                && garments[i].swing.isAtRest
        }
    }
}

/// How the other garments clear the stage when one becomes the hero.
public enum RailExit {
    /// −1 for garments left of the selection, +1 for those right of it, 0 for the selection.
    public static func direction(index: Int, selected: Int) -> Int {
        index == selected ? 0 : (index < selected ? -1 : 1)
    }

    /// Neighbours leave first, the far ends a beat later.
    public static func delay(index: Int, selected: Int, step: Double = 0.04) -> Double {
        index == selected ? 0 : Double(abs(index - selected) - 1) * step
    }

    /// Off-screen x offset for garment `index`: far enough that even the closest one clears
    /// a screen of `width`.
    public static func offset(index: Int, selected: Int, width: Double) -> Double {
        Double(direction(index: index, selected: selected)) * (width * 0.75 + Double(abs(index - selected)) * 24)
    }
}

/// An endless ticker: copies of one strip slide left forever.
public struct Marquee: Equatable, Sendable {
    /// pt/s.
    public var speed: Double
    /// Width of one copy of the content, including its trailing gap.
    public var itemWidth: Double

    public init(speed: Double = 40, itemWidth: Double) {
        self.speed = speed
        self.itemWidth = max(itemWidth, 0)
    }

    /// The strip's x offset at `time`, always in (−itemWidth, 0], so it wraps seamlessly.
    public func offset(at time: Double) -> Double {
        guard itemWidth > 0, time.isFinite, speed.isFinite else { return 0 }
        let r = (time * speed).truncatingRemainder(dividingBy: itemWidth)
        let o = -(r < 0 ? r + itemWidth : r)
        return o == -itemWidth ? 0 : (o == 0 ? 0 : o)
    }

    /// Copies needed so the strip always covers a `viewport` wide window.
    public static func copiesNeeded(viewport: Double, itemWidth: Double) -> Int {
        guard itemWidth > 0, viewport.isFinite else { return 1 }
        return Int((max(viewport, 0) / itemWidth).rounded(.up)) + 1
    }
}
