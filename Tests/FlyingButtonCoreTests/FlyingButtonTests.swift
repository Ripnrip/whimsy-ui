import Testing
@testable import FlyingButtonCore

/// Steps `model` at 60 fps for `seconds`, returning per-frame samples of (phase, lift).
@discardableResult
private func run(_ model: inout FlyingButtonModel, _ seconds: Double,
                 _ each: (FlyingButtonModel) -> Void = { _ in }) -> FlyingButtonModel {
    for _ in 0..<Int((seconds * 60).rounded()) { model.step(1.0 / 60); each(model) }
    return model
}

/// Holds for `hold` seconds, releases, and returns the model at release.
private func flight(seed: UInt64 = 1, hold: Double = 1.0) -> FlyingButtonModel {
    var m = FlyingButtonModel(seed: seed)
    m.pressBegan()
    run(&m, hold)
    return m
}

@Suite("Flight state machine")
struct StateMachineTests {
    @Test func startsIdleAndSettled() {
        let m = FlyingButtonModel()
        #expect(m.phase == .idle)
        #expect(m.lift == 0)
        #expect(m.isSettled)
        #expect(m.spawnRate == 0)
    }

    @Test func pressEntersThrustThenAirborneAfterSpoolUp() {
        var m = FlyingButtonModel()
        m.pressBegan()
        #expect(m.phase == .thrust)
        run(&m, 0.1)
        #expect(m.phase == .thrust)
        #expect(m.liftoffCount == 0)
        run(&m, 0.1)
        #expect(m.phase == .airborne)
        #expect(m.liftoffCount == 1)
    }

    @Test func thrustCrouchesBeforeLiftoff() {
        var m = FlyingButtonModel()
        m.pressBegan()
        var minLift = 0.0
        run(&m, 0.14) { minLift = min(minLift, $0.lift) }
        #expect(minLift < -0.8)
        #expect(minLift >= m.tuning.crouch - 0.5)
    }

    @Test func liftsToAboutHoverHeightAndBobs() {
        var m = flight(hold: 1.2)
        #expect(abs(m.lift - 24) < 3)
        var lo = Double.infinity, hi = -Double.infinity
        run(&m, 1.0) { lo = min(lo, $0.lift); hi = max(hi, $0.lift) }
        // A gentle hover: visible but small bob around ~24 pt.
        #expect(hi - lo > 1.5)
        #expect(hi - lo < 5)
        #expect(lo > 20 && hi < 28)
    }

    @Test func liftOvershootIsModest() {
        var m = FlyingButtonModel()
        m.pressBegan()
        var peak = 0.0
        run(&m, 1.0) { peak = max(peak, $0.lift) }
        #expect(peak > 24.5)
        #expect(peak < 31)
    }

    @Test func releaseLandsWithOneTinyBounceThenIdles() {
        var m = flight()
        m.pressEnded()
        #expect(m.phase == .landing)
        var bounceApex = 0.0, touched = false, minLift = 0.0
        run(&m, 1.5) { s in
            if s.touchdownCount == 1 { touched = true }
            if touched { bounceApex = max(bounceApex, s.lift) }
            minLift = min(minLift, s.lift)
        }
        #expect(m.touchdownCount == 1)
        #expect(bounceApex > 0.5)        // there *is* a visible bounce…
        #expect(bounceApex < 2.5)        // …and it is tiny
        #expect(minLift >= 0)            // never sinks through the ground
        #expect(m.phase == .idle)
        #expect(m.lift == 0)
    }

    @Test func touchdownIsSoftAndPrompt() {
        var m = flight()
        m.pressEnded()
        var t = 0.0, speed = 0.0
        while m.touchdownCount == 0 && t < 2 {
            speed = -m.liftVelocity
            m.step(1.0 / 240); t += 1.0 / 240
        }
        #expect(t > 0.15 && t < 0.6)      // a soft descent, not a drop…
        #expect(speed < 200)              // …landing well under 200 pt/s
    }

    @Test func shortPressAbortsWithoutLiftoff() {
        var m = FlyingButtonModel()
        m.pressBegan()
        run(&m, 0.05)
        m.pressEnded()
        #expect(m.phase == .landing)
        run(&m, 1.0)
        #expect(m.liftoffCount == 0)
        #expect(m.touchdownCount == 0)
        #expect(m.phase == .idle)
    }

    @Test func pressDuringLandingRelaunches() {
        var m = flight()
        m.pressEnded()
        run(&m, 0.1)
        m.pressBegan()
        #expect(m.phase == .thrust)
        run(&m, 0.3)
        #expect(m.phase == .airborne)
        #expect(m.liftoffCount == 2)
    }

    @Test func shadowShrinksAsItLifts() {
        let ground = FlyingButtonModel()
        let air = flight()
        #expect(ground.shadowScale == 1)
        #expect(air.shadowScale < 0.65)
        #expect(air.shadowOpacity < ground.shadowOpacity)
    }
}

@Suite("Plume emitter")
struct PlumeTests {
    @Test(arguments: [(FlightPhase.thrust, 140.0), (.airborne, 70.0)])
    func spawnRateByPhase(phase: FlightPhase, rate: Double) {
        var m = FlyingButtonModel()
        m.pressBegan()
        if phase == .airborne { run(&m, 0.3) }
        #expect(m.phase == phase)
        #expect(m.spawnRate == rate)
    }

    /// Births over a 0.14 s window starting from `model`.
    private func births(_ model: FlyingButtonModel) -> Int {
        var m = model, born = 0, last = m.particles.count
        for _ in 0..<Int(0.14 * 240) {
            m.step(1.0 / 240)
            born += max(m.particles.count - last, 0); last = m.particles.count
        }
        return born
    }

    @Test func thrustIsDenserThanHover() {
        var thrust = FlyingButtonModel()
        thrust.pressBegan()
        let hover = flight(hold: 1.0)
        #expect(births(thrust) > births(hover))
    }

    @Test func emitterStopsAfterLanding() {
        var m = flight()
        #expect(!m.particles.isEmpty)
        m.pressEnded()
        run(&m, 2.0)
        #expect(m.particles.isEmpty)
        #expect(m.isSettled)
    }

    @Test func puffsSpawnUnderTheCapsuleAndDriftDownAndOutward() {
        var m = flight(hold: 0.8)
        let young = m.particles.filter { $0.age < 0.02 }
        #expect(!young.isEmpty)
        for p in young {
            #expect(abs(p.position.y - (-m.lift + 1)) < 3)
            #expect(abs(p.position.x) <= m.tuning.nozzleHalfWidth + 1)
            #expect(p.velocity.y > 0)                 // heading down
        }
        // Older puffs have spread wider than the nozzle and sit lower than the capsule.
        run(&m, 0.0)
        let old = m.particles.filter { $0.progress > 0.5 }
        #expect(!old.isEmpty)
        let spread = old.map { abs($0.position.x) }.max() ?? 0
        #expect(spread > m.tuning.nozzleHalfWidth)
        #expect(old.allSatisfy { $0.position.y > -m.lift })
    }

    @Test func puffsNeverPassThroughTheFloor() {
        var m = FlyingButtonModel()
        m.pressBegan()
        var deepest = -Double.infinity
        run(&m, 1.0) { s in deepest = max(deepest, s.particles.map(\.position.y).max() ?? deepest) }
        #expect(deepest <= m.tuning.floor + 1e-9)
    }

    @Test func puffsFadeSwellAndCool() {
        var p = PlumeParticle(position: .zero, velocity: .zero, age: 0, lifetime: 1, baseRadius: 3)
        #expect(p.opacity == 0)
        p.age = 0.1
        let early = (p.opacity, p.radius, p.heat)
        p.age = 0.8
        #expect(p.opacity < early.0)
        #expect(p.radius > early.1)
        #expect(p.heat < early.2)
        p.age = 1
        #expect(p.opacity == 0)
        #expect(p.radius == 3 * 2.6)
    }

    @Test func respectsParticleCap() {
        var t = FlyingButtonModel.Tuning()
        t.maxParticles = 12
        var m = FlyingButtonModel(seed: 3, tuning: t)
        m.pressBegan()
        var most = 0
        run(&m, 1.0) { most = max(most, $0.particles.count) }
        #expect(most <= 12)
    }
}

@Suite("Determinism and stepping")
struct DeterminismTests {
    @Test func sameSeedSameFlight() {
        #expect(flight(seed: 42) == flight(seed: 42))
    }

    @Test func differentSeedsDifferentPlume() {
        #expect(flight(seed: 1).particles != flight(seed: 2).particles)
    }

    @Test func liftIsFrameRateIndependent() {
        var a = FlyingButtonModel(seed: 9), b = FlyingButtonModel(seed: 9)
        a.pressBegan(); b.pressBegan()
        for _ in 0..<30 { a.step(1.0 / 30) }
        for _ in 0..<120 { b.step(1.0 / 120) }
        #expect(abs(a.lift - b.lift) < 1e-9)
        #expect(a.phase == b.phase)
    }

    @Test(arguments: [-1.0, 0.0, Double.nan])
    func ignoresNonPositiveSteps(dt: Double) {
        var m = flight()
        let before = m
        m.step(dt)
        #expect(m == before)
    }

    @Test func clampsHugeFrames() {
        var m = FlyingButtonModel()
        m.pressBegan()
        m.step(5)
        #expect(abs(m.time - 0.1) < 1e-9)
    }
}
