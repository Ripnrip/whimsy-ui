import Foundation

/// Everything the view needs: the turntable, the mechanism, the look controls, and the words for VoiceOver.
public struct GumballModel: Sendable {
    public static let candyNames = ["red", "yellow", "green", "blue", "pink", "orange"]
    public static let seeThroughRate = 4.0     // 1/second
    public static let noticeLife = 1.6

    public var turntable = Turntable()
    public private(set) var mech = GumballMechanism()
    public var swatch: GumballSwatch = .tomato
    public var wobble: Double = 0.5 { didSet { wobble = FigureEase.clamp01(wobble) } }
    public var labelsOn = true
    public private(set) var seeThrough = false
    /// 0...1, eased toward the see-through switch.
    public private(set) var xr: Double = 0
    public private(set) var announcement: String?
    public private(set) var announcementCount = 0
    public private(set) var notice: String?
    public private(set) var noticeAge: Double = 99
    public private(set) var pile = GumballPile.make()
    public var reduceMotion = false {
        didSet {
            mech.reduceMotion = reduceMotion
            turntable.reduceMotion = reduceMotion
            if reduceMotion { xr = seeThrough ? 1 : 0 }
        }
    }

    // The crank gesture
    private var grabbed = false
    private var grabStart = Vec2(0, 0)
    private var grabMoved = false
    private var pushedLock = false

    public init() {}

    // MARK: actions

    @discardableResult
    public mutating func insertCoin() -> Bool { mech.insertCoin() }
    public mutating func turnCrank() { mech.turnFully() }
    public mutating func tapCrank() { mech.tapCrank() }
    /// Turns the crank directly to a total angle in radians (it only goes forward).
    public mutating func dragCrank(to angle: Double) { mech.dragCrank(to: angle) }
    public mutating func setSeeThrough(_ on: Bool) {
        seeThrough = on
        if reduceMotion { xr = on ? 1 : 0 }
    }
    public mutating func toggleSeeThrough() { setSeeThrough(!seeThrough) }

    // MARK: crank gesture (points are in figure units: the camera's projected space)

    public var camera: FigureCamera { FigureCamera(yaw: turntable.yaw) }

    public func knobScreen(angle: Double) -> Vec2 { camera.project(GumballLayout.knobCentre(angle: angle)) }

    /// A press at `p`: true when it landed on the crank knob (so it should not turn the figure).
    public mutating func crankPress(at p: Vec2) -> Bool {
        let hit = (knobScreen(angle: mech.crankDisplay) - p).length <= GumballLayout.crankHitRadius
        grabbed = hit
        grabStart = p
        grabMoved = false
        pushedLock = false
        return hit
    }

    /// The crank angle whose knob is nearest the pointer, searched around where the crank is now.
    public func nearestCrankAngle(to p: Vec2) -> Double {
        let cam = camera
        var best = mech.crank, bestD = Double.infinity
        var a = mech.crank - 0.8
        while a <= mech.crank + 1.2 {
            let d = (cam.project(GumballLayout.knobCentre(angle: a)) - p).length
            if d < bestD { bestD = d; best = a }
            a += 0.03
        }
        return best
    }

    public mutating func crankMove(to p: Vec2) {
        guard grabbed else { return }
        if !grabMoved && (p - grabStart).length > 2.5 { grabMoved = true }
        guard grabMoved else { return }
        let target = nearestCrankAngle(to: p)
        if mech.isCrankFree {
            mech.dragCrank(to: min(target, mech.crank + 1.0))
        } else if target > mech.crank + 0.05 && !pushedLock {
            pushedLock = true
            mech.dragCrank(to: target)
        }
    }

    /// Lifting the finger: a press with no drag counts as a tap.
    public mutating func crankRelease() {
        guard grabbed else { return }
        grabbed = false
        if !grabMoved { mech.tapCrank() }
    }
    public var isGrabbingCrank: Bool { grabbed }

    // MARK: time

    /// Advances everything and returns the mechanism's events, in order.
    @discardableResult
    public mutating func advance(by dt: Double) -> [GumballEvent] {
        mech.advance(by: dt)
        turntable.advance(by: dt)
        noticeAge += dt
        if noticeAge > Self.noticeLife { notice = nil }
        let goal = seeThrough ? 1.0 : 0.0
        if reduceMotion { xr = goal } else {
            let k = 1 - exp(-Self.seeThroughRate * dt)
            xr += (goal - xr) * k
            if abs(goal - xr) < 0.002 { xr = goal }
        }
        let events = mech.takeEvents()
        for e in events { handle(e) }
        return events
    }

    private mutating func handle(_ e: GumballEvent) {
        switch e {
        case .coinRefused: say(notice: "Machine is busy")
        case .crankLocked: say(notice: "Insert a coin first")
        case .coinLanded: announce("Coin in. Turn the crank")
        case .gumballReleased: announce("Dispensing")
        case .gumballOut:
            let c = mech.prizeColor.map { Self.candyNames[$0 % Self.candyNames.count] } ?? "colourful"
            announce("A \(c) gumball is out")
        default: break
        }
    }

    private mutating func announce(_ s: String) { announcement = s; announcementCount += 1 }
    private mutating func say(notice s: String) { notice = s; noticeAge = 0 }

    public mutating func takeHaptics() -> [GumballHaptic] { mech.takeHaptics() }

    /// True when nothing on screen is changing, so a view can stop asking for frames.
    public var isIdle: Bool {
        let free = mech.phase == .ready || mech.phase == .unlocked
        let goal = seeThrough ? 1.0 : 0.0
        let pawlDone = mech.phase == .ready ? mech.pawl == 0 : mech.pawl == 1
        return free && mech.crank == mech.crankTarget && pawlDone && mech.lockedAge >= 0.5 && turntable.isSettled
            && xr == goal && notice == nil && !grabbed
    }

    // MARK: drawing

    public var statusText: String {
        switch mech.phase {
        case .ready: return mech.prizeColor == nil ? "Insert a coin" : "Take your gumball, or insert a coin"
        case .coinDropping: return "Clink"
        case .unlocked: return "Turn the crank"
        case .turning: return "Keep turning"
        case .dispensing: return "Dispensing"
        }
    }

    public var accessibilityValue: String {
        var s = statusText
        s += seeThrough ? ", see-through on" : ", see-through off"
        s += ", \(mech.dispensed) dispensed"
        return s
    }

    public var style: FigureStyle { FigureStyle(wobble: wobble, seed: 7) }

    public func pose() -> GumballLayout.Pose {
        var p = GumballLayout.Pose()
        p.crank = mech.crankDisplay
        p.wheel = mech.wheelAngle
        p.pawl = mech.pawl
        let d = mech.dispense
        p.flap = d?.flap ?? 0
        let rest = Vec3(GumballLayout.coinSlotX, 0, GumballLayout.coinRestZ)
        func older(_ n: Int) -> [Vec3] { (0..<max(0, min(n, 2))).map { Vec3(rest.x, -1.2 * Double($0 + 1), rest.z) } }
        if let f = mech.coinPosition {
            p.coins = [f] + older(mech.coinsLanded)
        } else if mech.coinsLanded > 0 {
            p.coins = [rest] + older(mech.coinsLanded - 1)
        }
        // Gumballs held in the wheel's pockets.
        let r = GumballLayout.ballRadius
        for k in 0..<GumballLayout.pocketCount where k != mech.emptyPocket && k != mech.reloadingPocket {
            var c = GumballLayout.pocketCentre(k, wheel: -mech.wheelAngle)
            c = Vec3(GumballLayout.ballPath[0].x, c.y, c.z)
            p.sprites.append(FigureSprite(id: GumballLayout.ID.pocketBall + k, layer: .interior, centre: c, radius: r,
                                          color: GumballCandy.color(mech.pocketColors[k]), half: Vec3(0.05, r, r)))
        }
        if let k = mech.reloadingPocket {
            let u = mech.reload
            if u > 0 {
                var target = GumballLayout.pocketCentre(k, wheel: -mech.wheelAngle)
                target = Vec3(GumballLayout.ballPath[0].x, target.y, target.z)
                let from = Vec3(GumballLayout.ballPath[0].x, 0, 51)
                let ball = FigureSprite(id: GumballLayout.ID.reloadBall, layer: .interior, centre: Vec3.lerp(from, target, u * u), radius: r,
                                        color: GumballCandy.color(mech.pocketColors[k]), alpha: min(1, u * 5), half: Vec3(0.05, r, r))
                p.sprites.append(ball)
            }
        }
        // The gumball on its way out, or waiting in the tray.
        let prize = GumballCandy.color(mech.prizeColor ?? 0)
        if let d = d {
            if d.alpha > 0 {
                p.sprites.append(FigureSprite(id: GumballLayout.ID.travelBall, layer: d.centre.x > 17.4 ? .hardware : .interior, centre: d.centre,
                                              radius: r, color: prize, alpha: d.alpha))
            }
        } else if mech.prizeColor != nil {
            p.sprites.append(FigureSprite(id: GumballLayout.ID.prize, layer: .hardware, centre: GumballLayout.ballPath[GumballLayout.ballPath.count - 1],
                                          radius: r, color: prize))
        }
        let drawn = mech.cycle + ((mech.phase == .dispensing && mech.reload > 0) ? 1 : 0)
        p.pileSkip = min(drawn, pile.balls.count - 1)
        return p
    }

    public func scene() -> FigureScene {
        GumballLayout.scene(pose: pose(), swatch: swatch, pile: pile, seeThrough: xr)
    }

    public func frame() -> FigureFrame {
        FigureRenderer.render(scene(), camera: camera, style: style)
    }

    /// The labels for the current view: nil-free, empty unless see-through is on with labels enabled.
    public func labels() -> [PlacedLabel] {
        guard labelsOn, xr > 0.05 else { return [] }
        return LabelLayout.place(camera: camera, active: mech.activeParts)
    }
}
