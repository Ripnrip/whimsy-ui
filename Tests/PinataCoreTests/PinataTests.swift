import Foundation
import Testing
@testable import PinataCore

extension PinataModel {
    @discardableResult
    mutating func run(_ seconds: Double, fps: Double = 60) -> [PinataEvent] {
        var out: [PinataEvent] = []
        let n = Int((seconds * fps).rounded())
        for _ in 0..<n { out += step(1 / fps) }
        return out
    }
}

@Suite("Math") struct PinataMathTests {
    @Test func anchorsMatchTheLibraryAtEasyAngles() {
        #expect(PinataMath.sin(0) == 0)
        #expect(abs(PinataMath.sin(PinataMath.halfPi) - 1) < 1e-12)
        #expect(abs(PinataMath.sin(PinataMath.pi)) < 1e-12)
        #expect(abs(PinataMath.cos(0) - 1) < 1e-12)
        #expect(PinataMath.exp(0) == 1)
        #expect(abs(PinataMath.exp(1) - 2.718281828459045) < 1e-12)
    }

    @Test func nonFiniteInputsStayFinite() {
        #expect(PinataMath.sin(.nan) == 0)
        #expect(PinataMath.sin(.infinity) == 0)
        #expect(PinataMath.exp(.nan) == 0)
        #expect(PinataMath.exp(80) == PinataMath.exp(60))
        #expect(PinataMath.exp(-80) == PinataMath.exp(-60))
    }
}

@Suite("Pendulum") struct PendulumTests {
    @Test func restIsAnEquilibrium() {
        var p = PinataPendulum()
        let bob = p.bob
        #expect(bob.x == PinataTuning.anchorX)
        #expect(abs(bob.y - (PinataTuning.anchorY + PinataTuning.restLength)) < 1e-9)
        p.substep(PinataTuning.substep)
        #expect(p.angle == 0 && p.omega == 0)
        #expect(p.length == PinataTuning.restLength && p.radialVelocity == 0)
    }

    @Test func localAndWorldRoundTrip() {
        var p = PinataPendulum()
        p.angle = 0.4
        p.length = 130
        let local = Vec2(12, -20)
        let back = p.localPoint(p.world(local))
        #expect(abs(back.x - local.x) < 1e-9)
        #expect(abs(back.y - local.y) < 1e-9)
        // Hanging, local up points toward the peg.
        p.angle = 0
        p.length = PinataTuning.restLength
        let crown = p.world(Vec2(0, -PinataTuning.bodyRadiusY))
        #expect(abs(crown.x - p.bob.x) < 1e-9)
        #expect(crown.y < p.bob.y)
        #expect(crown.y > PinataTuning.anchorY)
    }

    @Test func containsTheBodyAndNotThePeg() {
        let p = PinataPendulum()
        #expect(p.contains(p.bob))
        #expect(!p.contains(Vec2(PinataTuning.anchorX, PinataTuning.anchorY)))
        #expect(!p.contains(Vec2(-10, -10)))
        #expect(!p.contains(Vec2(.nan, 0)))
    }

    @Test func aHitDecaysBackTowardRest() {
        var m = PinataModel()
        #expect(m.strike(.left).contains(.hit(1, .left)))
        #expect(m.omega > 0)
        m.run(8)
        #expect(abs(m.angle) < 0.03)
        #expect(abs(m.omega) < 0.08)
        #expect(abs(m.length - PinataTuning.restLength) < 1)
    }

    @Test func angleAndLengthStayInsideTheStops() {
        var m = PinataModel(hitsToBreak: 24)
        for i in 0..<12 {
            _ = m.strike(i % 2 == 0 ? .left : .right)
            m.run(0.35)
            #expect(abs(m.angle) <= PinataTuning.maxAngle + 1e-9)
            #expect(m.length >= PinataTuning.minLength - 1e-9)
            #expect(m.length <= PinataTuning.maxLength + 1e-9)
        }
    }
}

@Suite("Hits") struct HitTests {
    @Test func missesAndBadInputDoNothing() {
        var m = PinataModel()
        #expect(m.hit(at: Vec2(0, 0)) == [])
        #expect(m.hit(at: Vec2(.nan, 1)) == [])
        #expect(m.step(0) == [] && m.step(-1) == [] && m.step(.nan) == [])
        #expect(m.hits == 0 && m.phase == .intact)
        m.run(5) // a huge stretch of time, via many frames
        #expect(m.phase == .intact && m.hits == 0)
    }

    @Test func aLargeFrameDoesNotExplode() {
        var m = PinataModel()
        _ = m.strike(.left)
        _ = m.step(10)
        #expect(m.angle.isFinite && m.omega.isFinite && m.length.isFinite)
        #expect(abs(m.angle) <= PinataTuning.maxAngle + 1e-9)
    }

    @Test func sideChoosesTheSwing() {
        var left = PinataModel()
        let leftEvents = left.strike(.left)
        #expect(leftEvents == [.hit(1, .left)])
        #expect(abs(left.omega - PinataTuning.impulse(forHit: 1)) < 1e-12)
        #expect(left.radialVelocity == PinataTuning.radialKick)

        var right = PinataModel()
        #expect(right.strike(.right) == [.hit(1, .right)])
        #expect(abs(right.omega + PinataTuning.impulse(forHit: 1)) < 1e-12)
    }

    @Test func theCentreCountsAsTheRightSide() {
        var m = PinataModel()
        let events = m.hit(at: m.bodyCenter)
        #expect(events == [.hit(1, .right)])
    }

    @Test func impulsesEscalate() {
        var m = PinataModel(hitsToBreak: 8)
        var previous = 0.0
        for n in 1...8 {
            let before = m.omega
            _ = m.strike(.left)
            let delta = m.omega - before
            let expected = PinataTuning.impulse(forHit: n)
            #expect(abs(delta - expected) < 1e-9)
            #expect(delta > previous)
            previous = delta
        }
        #expect(PinataTuning.impulse(forHit: 8) > PinataTuning.impulse(forHit: 1) * 2)
    }

    @Test func cracksLengthenWithEachHit() {
        var m = PinataModel(hitsToBreak: 8)
        for _ in 0..<8 { _ = m.strike(.left) }
        #expect(m.cracks.count == 8)
        let spans = m.cracks.map(\.span)
        #expect(spans == spans.sorted())
        #expect(Set(spans).count == spans.count)
        for crack in m.cracks {
            #expect(crack.points.count == 3)
            let travel = crack.points[0].distance(to: crack.points[2])
            #expect(abs(travel - crack.span) < 1e-6)
        }
    }

    @Test func accessibilityAlternatesSides() {
        var m = PinataModel(hitsToBreak: 4)
        #expect(m.hitForAccessibility() == [.hit(1, .left)])
        #expect(m.hitForAccessibility() == [.hit(2, .right)])
        #expect(m.accessibilityValue == "2 of 4")
        #expect(m.pillText == PinataTuning.keepTapping)
    }

    @Test func hitsToBreakIsClamped() {
        #expect(PinataModel(hitsToBreak: 0).hitsToBreak == 1)
        #expect(PinataModel(hitsToBreak: -4).hitsToBreak == 1)
        #expect(PinataModel(hitsToBreak: 100).hitsToBreak == PinataTuning.maxHits)
        var quick = PinataModel(hitsToBreak: 1)
        let events = quick.strike(.right)
        #expect(events == [.hit(1, .right), .burst])
        #expect(quick.phase == .bursting)
        #expect(quick.pillText == PinataTuning.comeBack)
        #expect(quick.hit(at: quick.bodyCenter) == [])
    }
}

@Suite("Candy") struct CandyTests {
    @Test func eachHitThrowsBetweenSixAndTenCandies() {
        for seed in [PinataTuning.defaultSeed, UInt64(1), UInt64(99), UInt64(0xFFFF_FFFF)] {
            var m = PinataModel(hitsToBreak: 12, seed: seed)
            for n in 1...10 {
                let before = m.particles.count
                _ = m.strike(.left)
                let thrown = m.particles.count - before
                #expect(thrown >= PinataTuning.candyMin && thrown <= PinataTuning.candyMax)
                #expect(m.particles.suffix(thrown).allSatisfy { $0.kind == .candy })
                #expect(n == m.hits)
            }
        }
    }

    @Test func theSameSeedReplaysAndAnotherSeedDoesNot() {
        func snapshot(_ seed: UInt64) -> [PinataParticle] {
            var m = PinataModel(seed: seed)
            _ = m.strike(.left)
            _ = m.strike(.right)
            return m.particles
        }
        #expect(snapshot(7) == snapshot(7))
        #expect(snapshot(7) != snapshot(8))
    }

    @Test func candyFallsAndThenDisappears() {
        var m = PinataModel(hitsToBreak: 12)
        _ = m.strike(.left)
        let y0 = m.particles.map(\.position.y).reduce(0, +) / Double(m.particles.count)
        m.run(0.25)
        let y1 = m.particles.map(\.position.y).reduce(0, +) / Double(max(m.particles.count, 1))
        #expect(y1 > y0)
        m.run(2)
        #expect(m.particles.isEmpty)
        #expect(m.glow == 0)
    }

    @Test func glowFadesButSurvivesTheFirstMoments() {
        var m = PinataModel()
        _ = m.strike(.left)
        #expect(m.glow == 1)
        m.run(0.12)
        #expect(m.glow < 0.7 && m.glow > 0.05)
    }
}

@Suite("Burst") struct BurstTests {
    private func broken() -> PinataModel {
        var m = PinataModel()
        for i in 0..<7 { _ = m.strike(i % 2 == 0 ? .left : .right); m.run(0.05) }
        return m
    }

    @Test func theEighthHitSplitsTheBody() {
        var m = broken()
        #expect(m.phase == .intact && m.hits == 7)
        let events = m.strike(.right)
        #expect(events == [.hit(8, .right), .burst])
        #expect(m.phase == .bursting)
        #expect(m.halves.count == 2)
        #expect(m.halves.map(\.side) == [.left, .right])
        #expect(m.token.present && m.token.scale == 0)
        #expect(m.particles.filter { $0.kind == .confetti }.count == PinataTuning.confettiCount)
        #expect(m.pillText == "Come back tomorrow")
        #expect(m.accessibilityValue == "Come back tomorrow")
    }

    @Test func halvesFallApartAndTheTokenRises() {
        var m = broken()
        _ = m.strike(.right)
        let left0 = m.halves[0].position
        let right0 = m.halves[1].position
        let token0 = m.token.offset
        let gap0 = right0.x - left0.x
        #expect(gap0 > 0)
        m.run(0.55)
        let gap1 = m.halves[1].position.x - m.halves[0].position.x
        #expect(gap1 > gap0 + 20)
        #expect(m.halves[0].position.y > left0.y)
        #expect(m.halves[1].position.y > right0.y)
        #expect(m.token.scale > 0.4)
        #expect(m.token.offset < token0)
        let settled = m.run(1.4)
        #expect(settled.contains(.settled))
        #expect(m.phase == .spent)
        #expect(m.run(0.5).isEmpty)
        #expect(m.halves.allSatisfy { $0.opacity == 0 })
    }

    @Test func resetPutsItBack() {
        var m = broken()
        _ = m.strike(.left)
        m.run(0.2)
        m.reset()
        #expect(m.phase == .intact && m.hits == 0 && m.cracks.isEmpty && m.particles.isEmpty)
        #expect(m.halves.isEmpty && m.token.present == false)
        #expect(m.angle == 0 && m.pillText == "Keep tapping")
        #expect(m.accessibilityValue == "0 of 8")
    }
}

@Suite("Reduce Motion") struct PinataReduceMotionTests {
    @Test func noSwingAndNoParticles() {
        var m = PinataModel(reduceMotion: true)
        for _ in 0..<4 {
            _ = m.hitForAccessibility()
            m.run(0.2)
        }
        #expect(m.angle == 0 && m.omega == 0)
        #expect(m.length == PinataTuning.restLength)
        #expect(m.particles.isEmpty)
        #expect(m.cracks.count == 4)
        #expect(m.accessibilityValue == "4 of 8")
        #expect(m.halves.isEmpty)
    }

    @Test func theBreakIsAFade() {
        var m = PinataModel(reduceMotion: true)
        var burst: [PinataEvent] = []
        for _ in 0..<8 { burst = m.hitForAccessibility() }
        #expect(burst == [.hit(8, .right), .burst])
        #expect(m.particles.isEmpty && m.halves.isEmpty)
        #expect(m.reveal == 0)
        m.run(0.2)
        #expect(m.phase == .bursting)
        #expect(m.reveal > 0.4 && m.reveal < 1)
        #expect(m.token.scale == m.reveal)
        #expect(m.angle == 0)
        let tail = m.run(0.3)
        #expect(tail.contains(.settled))
        #expect(m.phase == .spent && m.reveal == 1 && m.token.scale == 1)
        #expect(m.pillText == PinataTuning.comeBack)
    }

    @Test func switchingOnMidSwingDropsTheMotion() {
        var m = PinataModel()
        _ = m.strike(.left)
        m.run(0.1)
        #expect(abs(m.angle) > 0.01)
        #expect(!m.particles.isEmpty)
        m.setReduceMotion(true)
        #expect(m.angle == 0 && m.particles.isEmpty)
        m.run(0.2)
        #expect(m.angle == 0 && m.particles.isEmpty && m.hits == 1)
    }
}
