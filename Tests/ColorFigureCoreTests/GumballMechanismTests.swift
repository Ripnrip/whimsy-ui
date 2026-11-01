import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct GumballMechanismTests {
    /// Insert a coin and let it land.
    func unlocked() -> GumballMechanism {
        var m = GumballMechanism()
        m.insertCoin()
        m.advance(by: GumballMechanism.coinTotal + 0.05)
        return m
    }

    @Test func startsReadyAndLocked() {
        let m = GumballMechanism()
        #expect(m.phase == .ready)
        #expect(!m.isCrankFree)
        #expect(m.crank == 0 && m.dispensed == 0 && m.prizeColor == nil)
    }

    @Test func theCrankIsLockedUntilACoinIsIn() {
        var m = GumballMechanism()
        m.dragCrank(to: 1)
        m.tapCrank()
        m.turnFully()
        let ev = m.takeEvents()
        #expect(m.crank == 0 && m.phase == .ready)
        #expect(ev == [.crankLocked, .crankLocked, .crankLocked])
    }

    @Test func pushingTheLockedCrankWobblesItBriefly() {
        var m = GumballMechanism()
        m.tapCrank()
        m.advance(by: 0.05)
        #expect(m.crankDisplay != m.crank)
        m.advance(by: 0.6)
        #expect(m.crankDisplay == m.crank)
    }

    @Test func coinGoesInAndUnlocksTheMechanism() {
        var m = GumballMechanism()
        let accepted = m.insertCoin()
        #expect(accepted)
        #expect(m.phase == .coinDropping)
        m.advance(by: 0.37)
        #expect(m.phase == .coinDropping)
        let slot = m.coinPosition!
        #expect(abs(slot.x - GumballLayout.coinSlotX) < 1e-6)
        m.advance(by: 0.6)
        #expect(m.phase == .unlocked && m.isCrankFree)
        #expect(m.coinPosition == nil && m.coinsLanded == 1)
        let got1 = m.takeEvents()
        #expect(got1 == [.coinInserted, .coinLanded, .unlocked])
    }

    @Test func coinSlidesInThenFalls() {
        var m = GumballMechanism()
        m.insertCoin()
        let z0 = m.coinPosition!.z
        m.advance(by: 0.15)
        let mid = m.coinPosition!
        #expect(mid.x < GumballLayout.coinStart.x && mid.x > GumballLayout.coinSlotX && mid.z == z0)
        m.advance(by: 0.3)
        let fall = m.coinPosition!
        #expect(fall.z < z0 && fall.z >= GumballLayout.coinRestZ)
    }

    @Test func aSecondCoinIsRefused() {
        var m = unlocked()
        _ = m.takeEvents()
        let again = m.insertCoin()
        #expect(!again)
        let got2 = m.takeEvents()
        #expect(got2 == [.coinRefused])
        #expect(m.coinsInserted == 1)
    }

    @Test func pawlReleasesWhenUnlocked() {
        var m = GumballMechanism()
        #expect(m.pawl == 0)
        m.insertCoin()
        m.advance(by: GumballMechanism.coinTotal + 0.3)
        #expect(m.pawl == 1)
    }

    @Test func turningTheCrankStartsTheTurn() {
        var m = unlocked()
        _ = m.takeEvents()
        m.dragCrank(to: 0.5)
        #expect(m.phase == .turning && abs(m.crank - 0.5) < 1e-12)
        let got3 = m.takeEvents()
        #expect(got3 == [.crankStarted])
    }

    @Test func theCrankOnlyTurnsForward() {
        var m = unlocked()
        m.dragCrank(to: 1.2)
        m.dragCrank(to: 0.4)
        #expect(abs(m.crank - 1.2) < 1e-12)
    }

    @Test func eightDetentsPerTurn() {
        var m = unlocked()
        _ = m.takeEvents()
        m.dragCrank(to: 2 * Double.pi)
        let detents = m.takeEvents().compactMap { e -> Int? in if case .detent(let i) = e { return i } else { return nil } }
        #expect(detents == Array(1...8))
    }

    @Test func detentsFireOncePerStepWhenTurningSlowly() {
        var m = unlocked()
        _ = m.takeEvents()
        var seen: [Int] = []
        var a = 0.0
        while a < 2 * Double.pi - 0.01 {
            a += 0.01
            m.dragCrank(to: a)
            for e in m.takeEvents() { if case .detent(let i) = e { seen.append(i) } }
        }
        #expect(seen == Array(1...7))
        m.dragCrank(to: 7)
        for e in m.takeEvents() { if case .detent(let i) = e { seen.append(i) } }
        #expect(seen == Array(1...8))
    }

    @Test func aFullTurnStartsTheDispense() {
        var m = unlocked()
        _ = m.takeEvents()
        m.dragCrank(to: 7)                      // beyond a turn is clamped
        #expect(m.phase == .dispensing && m.crank == GumballMechanism.fullTurn)
        let ev = m.takeEvents()
        #expect(ev.contains(.turnComplete) && ev.contains(.gumballReleased))
        #expect(m.prizeColor != nil)
    }

    @Test func gumballComesOutThenTheMachineResets() {
        var m = unlocked()
        _ = m.takeEvents()
        m.dragCrank(to: 7)
        _ = m.takeEvents()
        m.advance(by: GumballMechanism.chuteTime - 0.05)
        #expect(m.dispensed == 0)
        m.advance(by: 0.1)
        #expect(m.dispensed == 1)
        let got4 = m.takeEvents()
        #expect(got4 == [.gumballOut])
        m.advance(by: GumballMechanism.dispenseTotal)
        #expect(m.phase == .ready && m.crank == 0 && m.cycle == 1)
        let got5 = m.takeEvents()
        #expect(got5 == [.ready])
        #expect(m.prizeColor != nil)           // still waiting in the tray
    }

    @Test func theWholeStoryInOrder() {
        var m = GumballMechanism()
        var all: [GumballEvent] = []
        m.insertCoin()
        m.advance(by: 1)
        m.turnFully()
        for _ in 0..<400 { m.advance(by: 0.02); all += m.takeEvents() }
        let plain = all.filter { if case .detent = $0 { return false } else { return true } }
        #expect(plain == [.coinInserted, .coinLanded, .unlocked, .crankStarted, .turnComplete, .gumballReleased, .gumballOut, .ready])
        #expect(m.phase == .ready && m.dispensed == 1)
    }

    @Test func tapsTurnTheCrankAQuarterEach() {
        var m = unlocked()
        m.tapCrank()
        m.advance(by: 0.5)
        #expect(abs(m.crank - Double.pi / 2) < 1e-9)
        m.tapCrank(); m.tapCrank(); m.tapCrank()
        m.advance(by: 0.3)
        #expect(m.phase == .turning)
        m.advance(by: 1.5)
        #expect(m.phase == .dispensing || m.phase == .ready)
        #expect(m.dispensed == 1 || m.crank == GumballMechanism.fullTurn)
    }

    @Test func crankSpeedIsLimited() {
        var m = unlocked()
        m.turnFully()
        m.advance(by: 0.1)
        #expect(m.crank <= GumballMechanism.maxCrankSpeed * 0.1 + 1e-9 && m.crank > 0.3)
    }

    @Test func theWheelTurnsAQuarterPerCrankTurn() {
        var m = unlocked()
        m.dragCrank(to: Double.pi)
        #expect(abs(m.wheelAngle - Double.pi / 4) < 1e-12)
        m.dragCrank(to: 7)
        #expect(abs(m.wheelAngle - Double.pi / 2) < 1e-12)
        m.advance(by: 3)
        #expect(m.crank == 0 && abs(m.wheelAngle - Double.pi / 2) < 1e-12)    // wheel keeps its quarter turn
    }

    @Test func aLoadedPocketArrivesAtTheChuteAfterOneTurn() {
        var m = unlocked()
        let before = GumballLayout.pocketCentre(m.emptyPocket, wheel: -m.wheelAngle)
        #expect(abs(before.y - GumballLayout.ballPath[0].y) < 1e-9)       // the empty one waits at the station
        m.dragCrank(to: 7)
        let k = m.emptyPocket                                              // now the one that just dropped its ball
        let c = GumballLayout.pocketCentre(k, wheel: -m.wheelAngle)
        #expect(abs(c.y - GumballLayout.ballPath[0].y) < 1e-9 && abs(c.z - GumballLayout.ballPath[0].z) < 1e-9)
    }

    @Test func theFreshlyEmptiedPocketGoesToTheTopToBeRefilled() {
        var m = unlocked()
        m.dragCrank(to: 7)
        let k = m.reloadingPocket!
        let c = GumballLayout.pocketCentre(k, wheel: -m.wheelAngle)
        #expect(abs(c.y) < 1e-9 && abs(c.z - (GumballLayout.wheelCentreZ + GumballLayout.pocketRadius)) < 1e-9)
        m.advance(by: 0.05)
        #expect(m.reload == 0)
        m.advance(by: 0.5)
        #expect(m.reload > 0.4)
        m.advance(by: 2)
        #expect(m.reloadingPocket == nil && m.pocketColors.count == 4)
    }

    @Test func theGumballTravelsTheChuteThenTheFlapThenRests() {
        let path = GumballLayout.ballPath
        let start = GumballMechanism.sample(at: 0, reduceMotion: false)!
        #expect((start.centre - path[0]).length < 1e-9 && start.inChute)
        let atFlap = GumballMechanism.sample(at: GumballMechanism.chuteTime, reduceMotion: false)!
        #expect((atFlap.centre - path[GumballLayout.flapIndex]).length < 1e-6)
        let end = GumballMechanism.sample(at: GumballMechanism.dispenseTotal, reduceMotion: false)!
        #expect((end.centre - path[path.count - 1]).length < 1e-6 && !end.inChute)
    }

    @Test func theGumballStaysOnItsPathThroughTheChute() {
        let path = GumballLayout.ballPath
        var lastZ = 1e9
        var t = 0.0
        while t <= GumballMechanism.chuteTime {
            let p = GumballMechanism.sample(at: t, reduceMotion: false)!.centre
            var best = 1e9
            for i in 0..<GumballLayout.flapIndex {
                let a = path[i], b = path[i + 1]
                let ab = b - a
                let u = max(0, min(1, (p - a).dot(ab) / ab.dot(ab)))
                best = min(best, (a + ab * u - p).length)
            }
            #expect(best < 1e-6)
            #expect(p.z <= lastZ + 1e-9)             // only ever falls
            lastZ = p.z
            t += 0.02
        }
    }

    @Test func theBallIsVisibleOutsideOnlyAfterTheFlap() {
        let a = GumballMechanism.sample(at: 0.5, reduceMotion: false)!.centre
        let b = GumballMechanism.sample(at: 1.4, reduceMotion: false)!.centre
        #expect(a.x < GumballLayout.frontX)
        #expect(b.x > GumballLayout.frontX)
        #expect(b.z >= 6.6 - 1e-6)
    }

    @Test func flapOpensForTheBall() {
        #expect(GumballMechanism.flapOpenness(at: 0.2) == 0)
        #expect(GumballMechanism.flapOpenness(at: 1.0) == 1)
        #expect(GumballMechanism.flapOpenness(at: 1.6) == 0)
        let mid = GumballMechanism.flapOpenness(at: 0.72)
        #expect(mid > 0 && mid < 1)
        // Fully open by the time the ball reaches the flap, shut again after it has gone.
        #expect(GumballMechanism.flapOpenness(at: GumballMechanism.chuteTime) == 1)
    }

    @Test func prizeStaysUntilTheNextCoin() {
        var m = unlocked()
        m.dragCrank(to: 7)
        m.advance(by: 3)
        #expect(m.prizeColor != nil)
        m.insertCoin()
        #expect(m.prizeColor == nil)
    }

    @Test func hapticsFireOnCoinDetentsAndGumball() {
        var m = GumballMechanism()
        m.insertCoin()
        m.advance(by: 1)
        m.turnFully()
        m.advance(by: 4)
        let h = m.takeHaptics()
        #expect(h.first == .coin && h.last == .gumball)
        #expect(h.filter { $0 == .detent }.count == 7)        // the eighth detent is the turn completing, which has none of its own
        #expect(h.count == 9)
    }

    @Test func hapticsAreDebounced() {
        var m = unlocked()
        _ = m.takeHaptics()
        m.advance(by: 0.2)
        m.dragCrank(to: 2.0)                                  // many detents in a single move
        let got6 = m.takeHaptics()
        #expect(got6 == [.detent])
    }

    @Test func reduceMotionSkipsTheCoinAndTheTravel() {
        var m = GumballMechanism()
        m.reduceMotion = true
        m.insertCoin()
        #expect(m.phase == .unlocked && m.coinPosition == nil && m.pawl == 1)
        m.dragCrank(to: 7)
        #expect(m.phase == .dispensing)
        m.advance(by: 0.2)
        #expect(m.dispensed == 1)
        let d = m.dispense!
        #expect(d.flap == 0 && !d.inChute && d.alpha > 0)
        m.advance(by: 0.4)
        #expect(m.phase == .ready)
    }

    @Test func labelsLightWhileTheirPartsWork() {
        var m = GumballMechanism()
        #expect(m.activeParts.isEmpty)
        m.insertCoin()
        m.advance(by: 0.1)
        #expect(m.activeParts == ["coinSlot"])
        m.advance(by: 0.4)
        #expect(m.activeParts == ["coinMech"])
        m.advance(by: 0.5)
        #expect(m.activeParts == ["coinMech"])               // unlocked: the mech is still the thing to look at
        m.turnFully()
        m.advance(by: 0.2)
        #expect(m.activeParts == ["crank", "shaft", "wheel"])
        m.advance(by: 0.5)
        #expect(m.phase == .turning || m.phase == .dispensing)
    }

    @Test func labelsGoDarkWhenTheCrankIsLeftAlone() {
        var m = unlocked()
        m.dragCrank(to: 1)
        #expect(m.activeParts.contains("crank"))
        m.advance(by: 0.4)
        #expect(m.activeParts.isEmpty)
    }

    @Test func chuteAndFlapLightDuringTheDispense() {
        var m = unlocked()
        m.dragCrank(to: 7)
        #expect(m.activeParts == ["wheel", "chute"])
        m.advance(by: 0.5)
        #expect(m.activeParts == ["chute"])
        m.advance(by: 0.5)
        #expect(m.activeParts == ["flap", "spring"])
        m.advance(by: 1.5)
        #expect(m.activeParts.isEmpty)
    }

    @Test func aSecondCycleUsesTheNextPocket() {
        var m = unlocked()
        m.dragCrank(to: 7); m.advance(by: 3)
        let first = m.emptyPocket
        m.insertCoin(); m.advance(by: 1)
        m.dragCrank(to: 7); m.advance(by: 3)
        #expect(m.dispensed == 2 && m.cycle == 2)
        #expect(m.emptyPocket == (first + 1) % 4)
    }
}
