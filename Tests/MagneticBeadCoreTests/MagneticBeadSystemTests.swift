import Testing
@testable import MagneticBeadCore

/// Runs the simulation at 60 fps for `seconds`.
private func simulate(_ system: inout MagneticBeadSystem, seconds: Double, fps: Double = 60) {
    let frames = Int((seconds * fps).rounded())
    for _ in 0..<frames { system.step(dt: 1 / fps) }
}

@Suite("Steps & snapping")
struct SteppingTests {
    @Test(arguments: [
        (0.0, 4, 0.0), (0.12, 4, 0.0), (0.13, 4, 0.25), (0.62, 4, 0.5), (0.63, 4, 0.75),
        (0.99, 4, 1.0), (1.7, 4, 1.0), (-0.3, 4, 0.0), (0.333, 0, 0.333), (0.5, 1, 1.0),
    ])
    func snapToNearestStep(input: Double, steps: Int, expected: Double) {
        #expect(abs(MagneticBeadSystem.snap(input, steps: steps) - expected) < 1e-12)
    }

    @Test func nonFiniteInputClampsToZero() {
        #expect(MagneticBeadSystem.snap(.nan, steps: 4) == 0)
        #expect(MagneticBeadSystem.snap(.infinity, steps: 0) == 0)
    }

    @Test func stepIndexIsNilWhenContinuous() {
        #expect(MagneticBeadSystem.stepIndex(for: 0.5, steps: 0) == nil)
        #expect(MagneticBeadSystem.stepIndex(for: 0.5, steps: 10) == 5)
        #expect(MagneticBeadSystem(steps: 0).stepSize == nil)
        #expect(MagneticBeadSystem(steps: 8).stepSize == 0.125)
    }

    @Test func initialValueIsSnappedAndSettled() {
        let system = MagneticBeadSystem(value: 0.3, steps: 4)
        #expect(system.value == 0.25)
        #expect(system.thumbPosition == 0.25)
        #expect(system.isSettled)
        #expect(system.beads.count == 8)
    }

    @Test func dragReportsStepCrossingsOnly() {
        var system = MagneticBeadSystem(value: 0, steps: 4)
        let small = system.drag(to: 0.1)      // nearest step still 0
        let cross = system.drag(to: 0.2)      // nearest step becomes 1
        let same = system.drag(to: 0.3)       // still 1
        let back = system.drag(to: 0.05)      // back to 0
        #expect(!small)
        #expect(cross)
        #expect(!same)
        #expect(back)
    }

    @Test func fastDragAcrossManyStepsReportsCrossing() {
        var system = MagneticBeadSystem(value: 0, steps: 10)
        let crossed = system.drag(to: 0.9)
        #expect(crossed)
        #expect(system.stepIndex == 9)
    }

    @Test func continuousSliderNeverReportsCrossing() {
        var system = MagneticBeadSystem(value: 0, steps: 0)
        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            let crossed = system.drag(to: x)
            #expect(!crossed)
        }
        #expect(abs(system.release() - 1.0) < 1e-9)
    }

    @Test func dragClampsToTrack() {
        var system = MagneticBeadSystem(steps: 4)
        system.drag(to: 1.4)
        #expect(system.thumbPosition == 1)
        system.drag(to: -2)
        #expect(system.thumbPosition == 0)
    }

    @Test func releaseSnapsWithSpringThenSettles() {
        var system = MagneticBeadSystem(value: 0, steps: 4)
        system.drag(to: 0.4)
        let snapped = system.release()
        #expect(snapped == 0.5)
        #expect(system.thumbTarget == 0.5)
        #expect(system.thumbPosition == 0.4)          // hasn't jumped
        system.step(dt: 1.0 / 60)
        #expect(system.thumbPosition > 0.4)           // springing toward 0.5
        simulate(&system, seconds: 3)
        #expect(system.isSettled)
        #expect(system.thumbPosition == 0.5)
        #expect(!system.isDragging)
    }

    @Test func setValueAnimatedVsImmediate() {
        var animated = MagneticBeadSystem(value: 0, steps: 4)
        let changed = animated.setValue(0.74)
        #expect(changed)
        #expect(animated.value == 0.75)
        #expect(animated.thumbPosition == 0)
        #expect(!animated.isSettled)

        var immediate = MagneticBeadSystem(value: 0, steps: 4)
        immediate.setValue(0.74, animated: false)
        #expect(immediate.thumbPosition == 0.75)
        #expect(immediate.isSettled)
    }
}

@Suite("Magnetic pull")
struct MagneticPullTests {
    @Test func falloffShape() {
        let system = MagneticBeadSystem()
        #expect(system.falloff(distance: 0) == 1)
        #expect(system.falloff(distance: 0.1) > system.falloff(distance: 0.2))
        #expect(system.falloff(distance: 1) < 1e-6)
    }

    @Test func nearbyBeadsArePulledTowardThumbFarOnesBarely() {
        var system = MagneticBeadSystem(value: 0, steps: 0)
        system.drag(to: 0.5)
        for i in system.beads.indices {
            let rest = system.beads[i].restPosition
            let target = system.targetPosition(forBead: i)
            // Pull always points toward the thumb and never overshoots it.
            if rest < 0.5 { #expect(target >= rest && target <= 0.5) }
            if rest > 0.5 { #expect(target <= rest && target >= 0.5) }
        }
        let near = system.beads.indices.min { abs(system.beads[$0].restPosition - 0.5) < abs(system.beads[$1].restPosition - 0.5) }!
        let nearShift = abs(system.targetPosition(forBead: near) - system.beads[near].restPosition)
        let farShift = abs(system.targetPosition(forBead: 0) - system.beads[0].restPosition)
        #expect(nearShift > farShift)
        #expect(farShift < 0.01)
    }

    @Test(arguments: stride(from: 0.0, through: 1.0, by: 0.05).map { $0 })
    func targetsPreserveBeadOrder(thumb: Double) {
        var system = MagneticBeadSystem()
        system.drag(to: thumb)
        let targets = system.beads.indices.map { system.targetPosition(forBead: $0) }
        #expect(zip(targets, targets.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func springsAreStifferNearThumb() {
        var system = MagneticBeadSystem()
        system.drag(to: 0)
        let near = system.spring(forBead: 0).stiffness
        let far = system.spring(forBead: system.beads.count - 1).stiffness
        #expect(near > far)
        #expect(abs(far - system.configuration.stiffness * system.configuration.farStiffnessFactor) < 1)
    }

    @Test func beadsTrailLikeAChain() {
        // Jump the thumb; beads near it should cover more of their journey early on than
        // beads further back (softer springs), i.e. the chain trails behind the magnet.
        var system = MagneticBeadSystem(value: 0, steps: 0)
        let start = system.beads.map(\.position)
        system.drag(to: 0.6)
        let targets = system.beads.indices.map { system.targetPosition(forBead: $0) }
        simulate(&system, seconds: 0.05)
        func progress(_ i: Int) -> Double {
            (system.beads[i].position - start[i]) / (targets[i] - start[i])
        }
        // Bead 4 rests at ~0.571 (right under the thumb); bead 2 at ~0.286 (well behind).
        #expect(abs(targets[2] - start[2]) > 0.01) // the far bead still has somewhere to go
        #expect(progress(4) > progress(2))
        #expect(!system.isSettled)
        simulate(&system, seconds: 4)
        #expect(system.isSettled)
    }
}

@Suite("Spring integrator")
struct SpringTests {
    @Test func dampedSpringConverges() {
        let spring = DampedSpring(stiffness: 200, dampingRatio: 0.6)
        var x = 0.0, v = 0.0
        for _ in 0..<600 { spring.step(position: &x, velocity: &v, target: 1, dt: 1.0 / 240) }
        #expect(abs(x - 1) < 1e-3)
        #expect(abs(v) < 1e-2)
    }

    @Test func underdampedSpringOvershootsCriticalDoesNot() {
        func peak(_ zeta: Double) -> Double {
            let spring = DampedSpring(stiffness: 200, dampingRatio: zeta)
            var x = 0.0, v = 0.0, peak = 0.0
            for _ in 0..<960 {
                spring.step(position: &x, velocity: &v, target: 1, dt: 1.0 / 240)
                peak = max(peak, x)
            }
            return peak
        }
        #expect(peak(0.4) > 1.05)
        #expect(peak(1.0) <= 1.0 + 1e-3)
    }

    @Test func largeFrameDeltaStaysStable() {
        var system = MagneticBeadSystem(value: 0, steps: 4)
        system.setValue(1)
        for _ in 0..<20 { system.step(dt: 5) }            // e.g. app returning from background
        #expect(system.beads.allSatisfy { $0.position.isFinite && abs($0.position) < 2 })
        #expect(system.isSettled)
    }

    @Test func zeroOrInvalidDeltaIsNoOp() {
        var system = MagneticBeadSystem(value: 0, steps: 4)
        system.setValue(1)
        let before = system
        system.step(dt: 0)
        system.step(dt: -1)
        system.step(dt: .nan)
        #expect(system == before)
    }

    @Test func frameRateIndependence() {
        var a = MagneticBeadSystem(value: 0, steps: 0)
        var b = a
        a.setValue(1); b.setValue(1)
        simulate(&a, seconds: 0.25, fps: 60)
        simulate(&b, seconds: 0.25, fps: 120)
        for i in a.beads.indices {
            #expect(abs(a.beads[i].position - b.beads[i].position) < 0.01)
        }
        #expect(abs(a.thumbPosition - b.thumbPosition) < 0.01)
    }
}

@Suite("Squash & stretch")
struct SquashTests {
    @Test(arguments: [0.0, 0.3, -0.3, 1, -2.5, 40, .nan])
    func squashPreservesArea(velocity: Double) {
        let s = MagneticBeadSystem().squash(forVelocity: velocity)
        #expect(abs(s.along * s.across - 1) < 1e-12)
        #expect(s.along >= 1)
    }

    @Test func atRestIsIdentity() {
        let system = MagneticBeadSystem()
        #expect(system.squash(forVelocity: 0) == .identity)
        #expect(system.beads.indices.allSatisfy { system.squash(forBead: $0) == .identity })
    }

    @Test func fasterStretchesMoreUpToCap() {
        let system = MagneticBeadSystem()
        let slow = system.squash(forVelocity: 0.5).along
        let fast = system.squash(forVelocity: 1.5).along
        let insane = system.squash(forVelocity: 1000).along
        #expect(fast > slow)
        #expect(insane == 1 + system.configuration.maxStretch)
        #expect(system.squash(forVelocity: -1.5) == system.squash(forVelocity: 1.5))
    }

    @Test func movingBeadsStretch() {
        var system = MagneticBeadSystem(value: 0, steps: 0)
        system.drag(to: 0.3)
        system.step(dt: 1.0 / 60)
        let maxAlong = system.beads.indices.map { system.squash(forBead: $0).along }.max()!
        #expect(maxAlong > 1)
    }
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test func customBeadCountAndSingleBead() {
        let five = MagneticBeadSystem(configuration: BeadConfiguration(beadCount: 5))
        #expect(five.beads.map(\.restPosition) == [0, 0.25, 0.5, 0.75, 1])
        let one = MagneticBeadSystem(configuration: BeadConfiguration(beadCount: 1))
        #expect(one.beads.map(\.restPosition) == [0.5])
    }

    @Test func negativeStepsTreatedAsContinuous() {
        let system = MagneticBeadSystem(value: 0.37, steps: -3)
        #expect(system.steps == 0)
        #expect(system.value == 0.37)
    }
}
