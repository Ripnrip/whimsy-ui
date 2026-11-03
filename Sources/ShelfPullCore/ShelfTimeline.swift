import Foundation

public enum ShelfPhase: Int, CaseIterable, Sendable {
    /// Every book is home.
    case resting
    /// A finger is pulling a book up.
    case dragging
    /// The book has been let go past the threshold and rises free toward the stage.
    case lifting
    /// It turns 90° about its vertical axis to show the front cover.
    case turning
    /// The cover has grown into a card; it stays until it is closed.
    case open
    /// Going home: the card shrinks to the cover, the book turns back and slides down into its slot
    /// (or, after a short pull, springs back).
    case returning
    /// The book has just landed: a thunk, and the neighbours rock once.
    case seating
}

public enum ShelfReturnKind: Int, Sendable {
    /// From the open card, with the 3D turn.
    case card
    /// A short pull let go: the book springs back home.
    case springBack
    /// From the open card under Reduce Motion: a crossfade.
    case fade
}

public struct ShelfSpineFrame: Equatable, Sendable {
    public var index: Int
    /// Points above its slot.
    public var rise: Double
    /// Degrees, positive = clockwise; the pivot is the bottom corner on `pivotsTrailing`'s side.
    public var lean: Double
    public var pivotsTrailing: Bool
    /// Horizontal shift toward the stage, points.
    public var offsetX: Double
    public var scale: Double
    /// Rotation about the vertical axis, 0 ... 90 degrees (0 = spine facing you, 90 = front cover).
    public var turn: Double
    public var opacity: Double
    public var isActive: Bool
}

public struct ShelfCard: Equatable, Sendable {
    /// 0 = the cover as it sits on the stage, 1 = the full card.
    public var progress: Double
    public var rect: ShelfRect
    public var cornerRadius: Double
    /// The mini demo's opacity.
    public var contentOpacity: Double
    /// The cover art's opacity (it fades out as the demo fades in).
    public var coverOpacity: Double
    /// The whole card, for the Reduce Motion crossfade.
    public var opacity: Double
}

public struct ShelfFrame: Equatable, Sendable {
    public var phase: ShelfPhase
    public var book: Int?
    public var spines: [ShelfSpineFrame]
    public var card: ShelfCard?
    /// How much the shelf is dimmed behind the card, 0 ... 0.5.
    public var scrim: Double
    /// The pull (points) and how far it is toward the commit distance, 0 ... 1.
    public var drag: Double
    public var pullProgress: Double
    /// True while the pull is past the commit distance.
    public var armed: Bool
}

/// The whole interaction as a pure function of the phase and the time spent in it.
public enum ShelfTimeline {
    public static let liftDuration = 0.45
    public static let turnDuration = 0.5
    public static let openDuration = 0.5
    public static let cardShrinkDuration = 0.4
    public static let turnBackDuration = 0.45
    public static let slideDuration = 0.55
    public static var cardReturnDuration: Double { cardShrinkDuration + turnBackDuration + slideDuration }
    public static let springBackDuration = 0.55
    public static let springStiffness = 260.0
    public static let springDamping = 0.85
    public static let fadeDuration = 0.25
    public static let seatDuration = 0.4
    public static let seatDurationReduced = 0.12
    public static let turnDegrees = 90.0
    public static let maxScrim = 0.5
    public static let cardCorner = 22.0
    public static let coverCorner = 4.0

    /// How long a phase lasts; nil for the ones that wait for the user (resting, dragging, open).
    public static func duration(_ phase: ShelfPhase, kind: ShelfReturnKind, reduceMotion: Bool) -> Double? {
        switch phase {
        case .resting, .dragging, .open: return nil
        case .lifting: return liftDuration
        case .turning: return turnDuration
        case .returning:
            switch kind {
            case .card: return cardReturnDuration
            case .springBack: return springBackDuration
            case .fade: return fadeDuration
            }
        case .seating: return reduceMotion ? seatDurationReduced : seatDuration
        }
    }

    /// The card can be closed once it has finished opening.
    public static func closeLockout(reduceMotion: Bool) -> Double { reduceMotion ? fadeDuration : openDuration }

    /// rise, offset and scale of the active book part of the way to the stage (`u` 0 = home, 1 = on stage).
    static func pose(layout: ShelfLayout, book: Int, u: Double) -> (rise: Double, offsetX: Double, scale: Double) {
        let s = layout.spines[book]
        return (layout.liftedRise(book) * u, (ShelfLayout.stage.x - s.centerX) * u, WhimsyMath.lerp(1, ShelfLayout.stageScale, u))
    }

    static func card(layout: ShelfLayout, book: Int, p: Double, opacity: Double) -> ShelfCard {
        let e = WhimsyMath.clamp01(p)
        return ShelfCard(progress: e, rect: ShelfRect.lerp(layout.coverRect(book), ShelfLayout.cardRect, e),
                         cornerRadius: WhimsyMath.lerp(coverCorner, cardCorner, e),
                         contentOpacity: WhimsyMath.smoothstep(0.55, 1, e), coverOpacity: 1 - WhimsyMath.smoothstep(0.35, 0.8, e),
                         opacity: opacity)
    }

    /// One frame. `drag` is the pull, `releaseRise` the rise at the moment of release, `t` the time in the phase.
    public static func frame(layout: ShelfLayout, phase: ShelfPhase, book: Int?, time t: Double, drag: Double = 0,
                             releaseRise: Double = 0, kind: ShelfReturnKind = .card, reduceMotion: Bool = false) -> ShelfFrame {
        let n = layout.count
        let time = t.isFinite ? max(t, 0) : 0
        var frames = (0..<n).map {
            ShelfSpineFrame(index: $0, rise: 0, lean: 0, pivotsTrailing: true, offsetX: 0, scale: 1, turn: 0, opacity: 1, isActive: false)
        }
        guard let b = book, b >= 0, b < n, phase != .resting else {
            return ShelfFrame(phase: .resting, book: nil, spines: frames, card: nil, scrim: 0, drag: 0, pullProgress: 0, armed: false)
        }
        let h = layout.spines[b].height
        var rise = 0.0, offsetX = 0.0, scale = 1.0, turn = 0.0, opacity = 1.0
        var card: ShelfCard?
        var scrim = 0.0, shownDrag = 0.0, armed = false
        var wobbleTime: Double?
        switch phase {
        case .resting: break
        case .dragging:
            shownDrag = drag.isFinite ? max(drag, 0) : 0
            rise = ShelfResistance.rise(forDrag: shownDrag, height: h)
            armed = shownDrag >= ShelfResistance.commitDistance(height: h)
        case .lifting:
            let e = WhimsyMath.easeOutCubic(time / liftDuration)
            let p = pose(layout: layout, book: b, u: e)
            rise = WhimsyMath.lerp(releaseRise, layout.liftedRise(b), e); offsetX = p.offsetX; scale = p.scale
        case .turning:
            let p = pose(layout: layout, book: b, u: 1)
            rise = p.rise; offsetX = p.offsetX; scale = p.scale
            turn = turnDegrees * WhimsyMath.easeInOutCubic(time / turnDuration)
        case .open:
            if reduceMotion {
                let o = WhimsyMath.smoothstep(0, 1, time / fadeDuration)
                card = Self.card(layout: layout, book: b, p: 1, opacity: o)
                scrim = maxScrim * o
            } else {
                let p = WhimsyMath.easeInOutCubic(time / openDuration)
                let ps = pose(layout: layout, book: b, u: 1)
                rise = ps.rise; offsetX = ps.offsetX; scale = ps.scale; turn = turnDegrees; opacity = 0
                card = Self.card(layout: layout, book: b, p: p, opacity: 1)
                scrim = maxScrim * p
            }
        case .returning:
            switch kind {
            case .springBack:
                rise = time >= springBackDuration ? 0
                    : max(0, releaseRise * (1 - WhimsySpring.stepResponse(at: time, stiffness: springStiffness, dampingRatio: springDamping)))
            case .fade:
                let o = 1 - WhimsyMath.smoothstep(0, 1, time / fadeDuration)
                card = Self.card(layout: layout, book: b, p: 1, opacity: o)
                scrim = maxScrim * o
            case .card:
                if time < cardShrinkDuration {
                    let p = 1 - WhimsyMath.easeInOutCubic(time / cardShrinkDuration)
                    let ps = pose(layout: layout, book: b, u: 1)
                    rise = ps.rise; offsetX = ps.offsetX; scale = ps.scale; turn = turnDegrees; opacity = 0
                    card = Self.card(layout: layout, book: b, p: p, opacity: 1)
                    scrim = maxScrim * p
                } else if time < cardShrinkDuration + turnBackDuration {
                    let ps = pose(layout: layout, book: b, u: 1)
                    rise = ps.rise; offsetX = ps.offsetX; scale = ps.scale
                    turn = turnDegrees * (1 - WhimsyMath.easeInOutCubic((time - cardShrinkDuration) / turnBackDuration))
                } else {
                    let u = 1 - WhimsyMath.easeInOutCubic((time - cardShrinkDuration - turnBackDuration) / slideDuration)
                    let ps = pose(layout: layout, book: b, u: u)
                    rise = ps.rise; offsetX = ps.offsetX; scale = ps.scale
                }
            }
        case .seating:
            wobbleTime = reduceMotion ? nil : time
        }
        let lean = ShelfLean.angles(layout: layout, lifted: b, rise: rise)
        for i in 0..<n {
            var angle = lean[i]
            if let w = wobbleTime, i != b {
                let d = abs(i - b)
                angle += Double(i < b ? 1 : -1) * ShelfLean.wobble(distance: d, at: w)
            }
            frames[i].lean = angle
            frames[i].pivotsTrailing = ShelfLean.pivotsOnTrailingCorner(angle)
        }
        frames[b].rise = rise; frames[b].offsetX = offsetX; frames[b].scale = scale; frames[b].turn = turn
        frames[b].opacity = opacity; frames[b].isActive = true
        let commit = ShelfResistance.commitDistance(height: h)
        return ShelfFrame(phase: phase, book: b, spines: frames, card: card, scrim: scrim, drag: shownDrag,
                          pullProgress: phase == .dragging ? WhimsyMath.clamp01(shownDrag / commit) : 0, armed: armed)
    }

    /// While a book turns, the visible width of its spine face and of its front cover, and where the hinge
    /// (the edge the two faces share) sits relative to the book's centre so the whole thing stays centred.
    public static func turnLayout(spineWidth w: Double, coverWidth d: Double, degrees: Double) -> (spine: Double, cover: Double, hinge: Double) {
        let a = WhimsyMath.clamp(degrees.isFinite ? degrees : 0, 0, 90) * Double.pi / 180
        let sw = w * cos(a), cw = d * sin(a)
        return (sw, cw, (sw - cw) / 2)
    }
}
