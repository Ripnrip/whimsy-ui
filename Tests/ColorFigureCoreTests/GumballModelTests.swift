import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct GumballModelTests {
    func ready() -> GumballModel {
        var m = GumballModel()
        m.insertCoin()
        m.advance(by: 1)
        return m
    }

    // MARK: pile and scene

    @Test func pileIsSeededAndFitsTheGlobe() {
        let a = GumballPile.make(), b = GumballPile.make()
        #expect(a.balls.count == GumballPile.count)
        for (x, y) in zip(a.balls, b.balls) { #expect(x.centre == y.centre && x.colorIndex == y.colorIndex) }
        for ball in a.balls {
            #expect((ball.centre - GumballLayout.globeCentre).length <= GumballLayout.globeRadius - GumballPile.ballRadius)
            #expect(ball.colorIndex >= 0 && ball.colorIndex < 6)
        }
        #expect(GumballPile.make(seed: 1).balls.map { $0.centre } != a.balls.map { $0.centre })
    }

    @Test func pileBallsDoNotOverlapAndTheLowestComesFirst() {
        let p = GumballPile.make().balls
        for i in 0..<p.count { for j in (i + 1)..<p.count { #expect((p[i].centre - p[j].centre).length >= GumballPile.ballRadius * 1.9 - 1e-9) } }
        #expect(p.first!.centre.z <= p.last!.centre.z)
    }

    @Test func everySolidHasAUniqueIdAndAName() {
        let s = GumballModel().scene()
        let ids = s.solids.map { $0.id }
        #expect(Set(ids).count == ids.count)
        #expect(s.solids.allSatisfy { !$0.part.isEmpty })
        #expect(s.solids.count > 30)
    }

    @Test func sceneHasTheBigPartsTheBriefAsksFor() {
        let parts = Set(GumballModel().scene().solids.map { $0.part })
        for p in ["cabinet", "coinSlot", "crankArm", "crankKnob", "flap", "wheel", "pocket", "hopper", "chute", "shaft", "coinMech", "pawl"] {
            #expect(parts.contains(p), "missing \(p)")
        }
        #expect(GumballModel().scene().globe != nil)
        #expect(GumballModel().scene().wires.count == 1)   // the spring
    }

    @Test func crankArmFollowsTheCrankAngle() {
        var m = ready()
        let tip0 = m.scene().solids.first { $0.part == "crankKnob" }!.centre
        m.dragCrank(to: Double.pi / 2)
        let tip1 = m.scene().solids.first { $0.part == "crankKnob" }!.centre
        // From hanging straight down to pointing to the left (clockwise from the front): z rises, y goes negative.
        #expect(tip1.z > tip0.z + 6)
        #expect(tip1.y < tip0.y - 6)
        #expect(abs(tip1.x - tip0.x) < 1e-9)
    }

    @Test func knobCentreMatchesTheKnobSolid() {
        var m = ready()
        for a in [0.0, 0.7, 2.0, 4.0] {
            m.dragCrank(to: a)
            let k = m.scene().solids.first { $0.part == "crankKnob" }!.centre
            let c = GumballLayout.knobCentre(angle: m.mech.crankDisplay)
            #expect(abs(k.y - c.y) < 1e-6 && abs(k.z - c.z) < 1e-6)
        }
    }

    @Test func flapAndSpringMoveTogether() {
        var m = ready()
        let closed = m.scene()
        m.dragCrank(to: 7)
        m.advance(by: 1.0)
        let open = m.scene()
        let f0 = closed.solids.first { $0.part == "flap" }!.bounds.max.x, f1 = open.solids.first { $0.part == "flap" }!.bounds.max.x
        #expect(f1 > f0 + 4)
        let len = { (s: FigureScene) -> Double in (s.wires[0].points.last! - s.wires[0].points.first!).length }
        #expect(len(open) > len(closed) + 0.5)       // the spring stretches as the flap opens
    }

    @Test func coinsShowOnlyOutsideUntilSeeThrough() {
        var m = GumballModel()
        m.insertCoin()
        m.advance(by: 0.1)
        #expect(m.frame().order.contains("coin"))           // still outside the slot
        m.advance(by: 0.5)
        #expect(!m.frame().order.contains("coin"))          // inside the case, hidden
        m.setSeeThrough(true)
        m.advance(by: 2)
        #expect(m.frame().order.contains("coin"))
    }

    @Test func pileLosesABallEachCycle() {
        var m = ready()
        #expect(m.pose().pileSkip == 0)
        m.dragCrank(to: 7)
        m.advance(by: 3)
        #expect(m.pose().pileSkip == 1)
    }

    @Test func trayShowsThePrizeAfterTheDispense() {
        var m = ready()
        m.dragCrank(to: 7)
        m.advance(by: 0.5)
        #expect(m.pose().sprites.contains { $0.id == GumballLayout.ID.travelBall && $0.layer == .interior })
        m.advance(by: 3)
        let prize = m.pose().sprites.first { $0.id == GumballLayout.ID.prize }
        #expect(prize != nil && prize!.layer == .hardware)
        #expect((prize!.centre - GumballLayout.ballPath.last!).length < 1e-9)
    }

    // MARK: controls

    @Test func seeThroughEasesIn() {
        var m = GumballModel()
        m.setSeeThrough(true)
        #expect(m.xr == 0)
        m.advance(by: 0.2)
        #expect(m.xr > 0.3 && m.xr < 1)
        m.advance(by: 3)
        #expect(m.xr == 1)
        m.toggleSeeThrough()
        m.advance(by: 3)
        #expect(m.xr == 0)
    }

    @Test func reduceMotionJumpsSeeThroughAndMotion() {
        var m = GumballModel()
        m.reduceMotion = true
        m.setSeeThrough(true)
        #expect(m.xr == 1)
        #expect(m.mech.reduceMotion && m.turntable.reduceMotion)
    }

    @Test func wobbleIsClamped() {
        var m = GumballModel()
        m.wobble = 3
        #expect(m.wobble == 1)
        m.wobble = -1
        #expect(m.wobble == 0)
    }

    @Test func swatchChangesTheBodyColourNotTheStructure() {
        var m = GumballModel()
        let a = m.frame()
        m.swatch = .cobalt
        let b = m.frame()
        #expect(a.order == b.order)
        #expect(a.items != b.items)
        #expect(a.items.count == b.items.count)
    }

    @Test func frameIsDeterministic() {
        let m = ready()
        #expect(m.frame().items == m.frame().items)
    }

    // MARK: crank gesture

    @Test func pressingTheKnobGrabsItAndPressingElsewhereDoesNot() {
        var m = GumballModel()
        let knob = m.knobScreen(angle: 0)
        let hit = m.crankPress(at: knob + Vec2(2, 1))
        #expect(hit && m.isGrabbingCrank)
        m.crankRelease()
        let miss = m.crankPress(at: knob + Vec2(60, 0))
        #expect(!miss)
    }

    @Test func nearestAngleRecoversTheTruthAtEveryYaw() {
        for yaw in stride(from: -32.0, to: 330, by: 45) {
            var m = ready()
            m.turntable.yaw = yaw
            m.dragCrank(to: 0.9)
            let target = m.knobScreen(angle: 1.3)
            let a = m.nearestCrankAngle(to: target)
            // A front-on crank is well determined; edge-on it is only determined to the ellipse's width.
            let truth = (m.knobScreen(angle: a) - target).length
            #expect(truth < 0.5)
        }
    }

    @Test func draggingTheKnobTurnsTheCrank() {
        var m = ready()
        _ = m.crankPress(at: m.knobScreen(angle: 0))
        var a = 0.0
        while a < 1.5 {
            a += 0.1
            m.crankMove(to: m.knobScreen(angle: a))
        }
        #expect(abs(m.mech.crank - a) < 0.08)
        #expect(m.mech.phase == .turning)
    }

    @Test func draggingAllTheWayRoundDispenses() {
        var m = ready()
        _ = m.crankPress(at: m.knobScreen(angle: 0))
        var a = 0.0
        while a < 2 * Double.pi + 0.2 {
            a += 0.15
            m.crankMove(to: m.knobScreen(angle: a))
        }
        m.crankRelease()
        #expect(m.mech.phase == .dispensing)
        m.advance(by: 3)
        #expect(m.mech.dispensed == 1)
    }

    @Test func aPressWithoutADragIsATap() {
        var m = ready()
        _ = m.crankPress(at: m.knobScreen(angle: 0))
        m.crankRelease()
        m.advance(by: 0.4)
        #expect(abs(m.mech.crank - Double.pi / 2) < 1e-6)
    }

    @Test func pushingTheLockedCrankWiggleAndSaysSo() {
        var m = GumballModel()
        _ = m.crankPress(at: m.knobScreen(angle: 0))
        m.crankMove(to: m.knobScreen(angle: 0.6))
        m.crankMove(to: m.knobScreen(angle: 0.9))
        m.crankRelease()
        m.advance(by: 0.05)
        #expect(m.notice == "Insert a coin first")
        #expect(m.mech.crank == 0)
        m.advance(by: 2)
        #expect(m.notice == nil)
    }

    // MARK: words

    @Test func announcementsFollowTheMachine() {
        var m = GumballModel()
        m.insertCoin()
        m.advance(by: 1)
        #expect(m.announcement == "Coin in. Turn the crank")
        let n = m.announcementCount
        m.turnCrank()
        m.advance(by: 1.5)
        #expect(m.announcement == "Dispensing")
        m.advance(by: 0.5)
        #expect(m.announcement!.hasSuffix("gumball is out") && m.announcement!.hasPrefix("A "))
        #expect(m.announcementCount == n + 2)
        let colour = m.announcement!.dropFirst(2).split(separator: " ").first.map(String.init)!
        #expect(GumballModel.candyNames.contains(colour))
    }

    @Test func statusTextWalksThroughThePhases() {
        var m = GumballModel()
        #expect(m.statusText == "Insert a coin")
        m.insertCoin()
        #expect(m.statusText == "Clink")
        m.advance(by: 1)
        #expect(m.statusText == "Turn the crank")
        m.dragCrank(to: 1)
        #expect(m.statusText == "Keep turning")
        m.dragCrank(to: 7)
        #expect(m.statusText == "Dispensing")
        m.advance(by: 3)
        #expect(m.statusText.hasPrefix("Take your gumball"))
        #expect(m.accessibilityValue.contains("1 dispensed"))
    }

    @Test func busyMachineSaysSo() {
        var m = ready()
        let accepted = m.insertCoin()
        m.advance(by: 0.01)
        #expect(!accepted)
        #expect(m.notice == "Machine is busy")
    }

    @Test func hapticsPassThroughTheModel() {
        var m = GumballModel()
        m.insertCoin()
        m.advance(by: 1)
        let h = m.takeHaptics()
        #expect(h == [.coin])
        let again = m.takeHaptics()
        #expect(again.isEmpty)
    }
}

@Suite struct LabelTests {
    @Test func eightPartsAreNamed() {
        #expect(LabelLayout.all.count == 8)
        #expect(Set(LabelLayout.all.map { $0.part }).count == 8)
        #expect(Set(LabelLayout.all.map { $0.part }) == ["coinSlot", "coinMech", "crank", "shaft", "wheel", "chute", "spring", "flap"])
    }

    @Test func labelsAreOffUnlessSeeThroughAndEnabled() {
        var m = GumballModel()
        #expect(m.labels().isEmpty)
        m.setSeeThrough(true)
        m.advance(by: 3)
        #expect(m.labels().count == 8)
        m.labelsOn = false
        #expect(m.labels().isEmpty)
    }

    @Test func pillsInAColumnNeverOverlap() {
        for yaw in stride(from: 0.0, to: 360, by: 20) {
            let placed = LabelLayout.place(camera: FigureCamera(yaw: yaw))
            #expect(placed.count == 8)
            for side in [PlacedLabel.Side.left, .right] {
                let col = placed.filter { $0.side == side }.sorted { $0.centre.y < $1.centre.y }
                for (a, b) in zip(col, col.dropFirst()) { #expect(b.centre.y - a.centre.y >= LabelLayout.pillHeight + LabelLayout.gap - 1e-9) }
            }
            let l = placed.filter { $0.side == .left }.count
            #expect(abs(l - (8 - l)) <= 4)
        }
    }

    @Test func pillsSitOutsideTheFigure() {
        for yaw in stride(from: 0.0, to: 360, by: 25) {
            let cam = FigureCamera(yaw: yaw)
            let b = LabelLayout.figureBounds(cam)
            for p in LabelLayout.place(camera: cam) {
                if p.side == .left { #expect(p.centre.x + p.width / 2 <= b.minX - LabelLayout.margin + 1e-9) }
                else { #expect(p.centre.x - p.width / 2 >= b.maxX + LabelLayout.margin - 1e-9) }
            }
        }
    }

    @Test func leaderLinesStartAtTheProjectedAnchor() {
        let cam = FigureCamera(yaw: -32)
        for p in LabelLayout.place(camera: cam) {
            let l = LabelLayout.all.first { $0.part == p.part }!
            #expect((p.anchor - cam.project(l.anchor)).length < 1e-9)
        }
    }

    @Test func activePartsAreFlagged() {
        let placed = LabelLayout.place(camera: FigureCamera(yaw: 0), active: ["crank", "wheel"])
        #expect(Set(placed.filter { $0.active }.map { $0.part }) == ["crank", "wheel"])
    }

    @Test func labelsLightUpWithTheMachine() {
        var m = GumballModel()
        m.setSeeThrough(true)
        m.advance(by: 3)
        m.insertCoin()
        m.advance(by: 0.1)
        #expect(Set(m.labels().filter { $0.active }.map { $0.part }) == ["coinSlot"])
        m.advance(by: 1)
        m.turnCrank()
        m.advance(by: 0.3)
        #expect(Set(m.labels().filter { $0.active }.map { $0.part }) == ["crank", "shaft", "wheel"])
    }

    @Test func widthGrowsWithText() {
        #expect(LabelLayout.width(of: "Pocket wheel") > LabelLayout.width(of: "Flap"))
    }
}
