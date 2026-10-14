import Testing
import Foundation
@testable import ShutterRevealCore

private func run(_ m: inout ApertureMotion, seconds: Double, fps: Double = 60) -> [Double] {
    var trace: [Double] = []
    for _ in 0..<Int((seconds * fps).rounded()) { m.step(dt: 1 / fps); trace.append(m.progress) }
    return trace
}

@Suite("Aperture spring")
struct ApertureMotionTests {
    @Test func openingOvershootsThenSettles() {
        var m = ApertureMotion(isOpen: false, response: 0.45)
        m.setOpen(true)
        let trace = run(&m, seconds: 2.5)
        let peak = trace.max()!
        #expect(peak > 1.05 && peak < 1.2)   // ~11% overshoot at damping 0.58
        #expect(m.isSettled && m.progress == 1)
    }

    @Test func closingSnapsWithoutBouncingOpen() {
        var m = ApertureMotion(isOpen: true, response: 0.45)
        m.setOpen(false)
        let trace = run(&m, seconds: 1.5)
        #expect(trace.min()! > -0.02)          // at most a hair past shut (drawn clamped)
        #expect(m.isSettled && m.progress == 0)
        // Snappier than opening: shut within ~0.25 s.
        let shutFrame = trace.firstIndex { $0 <= ApertureMotion.closedThreshold }!
        #expect(Double(shutFrame + 1) / 60 < 0.25)
    }

    @Test func closeEventFiresOncePerClose() {
        var m = ApertureMotion(isOpen: true)
        m.setOpen(false); _ = run(&m, seconds: 1)
        #expect(m.closeEvents == 1)
        m.setOpen(true); _ = run(&m, seconds: 1.5)
        #expect(m.closeEvents == 1)              // opening never fires
        m.setOpen(false); _ = run(&m, seconds: 1)
        #expect(m.closeEvents == 2)
    }

    @Test func interruptedCloseStillFiresOnlyWhenShut() {
        var m = ApertureMotion(isOpen: true)
        m.setOpen(false); _ = run(&m, seconds: 0.03)
        m.setOpen(true); _ = run(&m, seconds: 1.5)   // reversed before shutting
        #expect(m.closeEvents == 0)
    }

    @Test func closingAnAlreadyClosedShutterDoesNotFire() {
        var m = ApertureMotion(isOpen: false)
        m.setOpen(false); _ = run(&m, seconds: 0.5)
        #expect(m.closeEvents == 0)
    }

    @Test func nonAnimatedJumps() {
        var m = ApertureMotion(isOpen: false)
        m.setOpen(true, animated: false)
        #expect(m.progress == 1 && m.velocity == 0 && m.isSettled)
    }

    @Test func shorterResponseIsFaster() {
        func timeToReach(_ response: Double) -> Int {
            var m = ApertureMotion(isOpen: false, response: response)
            m.setOpen(true)
            return run(&m, seconds: 2).firstIndex { $0 >= 0.9 }!
        }
        #expect(timeToReach(0.3) < timeToReach(0.6))
    }

    @Test func frameRateIndependent() {
        var a = ApertureMotion(), b = ApertureMotion()
        a.setOpen(true); b.setOpen(true)
        _ = run(&a, seconds: 0.3, fps: 60)
        _ = run(&b, seconds: 0.3, fps: 120)
        #expect(abs(a.progress - b.progress) < 0.01)
    }

    @Test func hugeAndInvalidStepsAreSafe() {
        var m = ApertureMotion()
        m.setOpen(true)
        for _ in 0..<50 { m.step(dt: 10) }
        #expect(m.progress.isFinite && abs(m.progress - 1) < 1e-3)
        let before = m
        m.step(dt: 0); m.step(dt: -1); m.step(dt: .nan)
        #expect(m == before)
    }

    @Test func drawableProgressClampsBelowZeroOnly() {
        var m = ApertureMotion(isOpen: true)
        m.setOpen(false)
        var minimum = 1.0
        for _ in 0..<90 { m.step(dt: 1 / 60); minimum = min(minimum, m.drawableProgress) }
        #expect(minimum >= 0)
    }

    @Test func changingResponseMidFlightKeepsState() {
        var m = ApertureMotion(isOpen: false, response: 0.45)
        m.setOpen(true); _ = run(&m, seconds: 0.1)
        let (p, v) = (m.progress, m.velocity)
        m.setResponse(0.3)
        #expect(m.progress == p && m.velocity == v)
        #expect(m.openSpring.response == 0.3 && abs(m.closeSpring.response - 0.165) < 1e-12)
        _ = run(&m, seconds: 2)
        #expect(m.isSettled && m.progress == 1)
    }

    @Test func springConstantsMatchSwiftUISemantics() {
        let s = ShutterSpring(response: 0.5, dampingFraction: 1)
        #expect(abs(s.stiffness - pow(2 * Double.pi / 0.5, 2)) < 1e-9)
        #expect(abs(s.damping - 2 * s.stiffness.squareRoot()) < 1e-9)   // critical at fraction 1
    }
}

@Suite("Motion blur ghosts")
struct MotionBlurTests {
    let g = IrisGeometry(bladeCount: 6, radius: 200, twist: 0.9)

    @Test func noGhostsAtRest() {
        #expect(MotionBlur.ghosts(progress: 0.5, velocity: 0, geometry: g).isEmpty)
        #expect(MotionBlur.ghosts(progress: 0.5, velocity: 0.01, geometry: g).isEmpty)
    }

    @Test func ghostsTrailBehindTheMotion() {
        let ghosts = MotionBlur.ghosts(progress: 0.5, velocity: 4, geometry: g)
        #expect(ghosts.count == 4)
        let now = g.rotation(progress: 0.5)
        for (i, ghost) in ghosts.enumerated() {
            let lag = Double(i + 1) / 240
            #expect(abs(ghost.rotation - (now - 4 * 0.9 * lag)) < 1e-12)    // −ω·i·Δt
            #expect(abs(ghost.progress - (0.5 - 4 * lag)) < 1e-12)
        }
        // Closing (negative velocity) trails the other way.
        let closing = MotionBlur.ghosts(progress: 0.5, velocity: -4, geometry: g)
        #expect(closing.allSatisfy { $0.rotation > now && $0.progress > 0.5 })
    }

    @Test func opacityFadesPerGhostAndScalesWithSpeed() {
        let slow = MotionBlur.ghosts(progress: 0.5, velocity: 0.5, geometry: g)
        let fast = MotionBlur.ghosts(progress: 0.5, velocity: 3, geometry: g)
        let insane = MotionBlur.ghosts(progress: 0.5, velocity: 300, geometry: g)
        #expect(zip(fast, fast.dropFirst()).allSatisfy { $0.opacity > $1.opacity })
        #expect(slow[0].opacity < fast[0].opacity)
        #expect(abs(insane[0].opacity - 0.18 * 0.8) < 1e-12)               // capped strength
    }

    @Test func ghostProgressNeverNegative() {
        let ghosts = MotionBlur.ghosts(progress: 0.01, velocity: 6, geometry: g)
        #expect(ghosts.allSatisfy { $0.progress >= 0 })
    }
}
