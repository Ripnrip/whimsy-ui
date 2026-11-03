import Testing
import Foundation
@testable import ShelfPullCore

private let L = ShelfLayout.make()

private func f(_ phase: ShelfPhase, _ t: Double = 0, book: Int = 3, drag: Double = 0, rise0: Double = 0,
               kind: ShelfReturnKind = .card, reduce: Bool = false) -> ShelfFrame {
    ShelfTimeline.frame(layout: L, phase: phase, book: book, time: t, drag: drag, releaseRise: rise0, kind: kind, reduceMotion: reduce)
}

@Suite struct ShelfTimelineTests {
    @Test func restingIsEverythingAtHome() {
        let r = ShelfTimeline.frame(layout: L, phase: .resting, book: nil, time: 3)
        #expect(r.phase == .resting && r.card == nil && r.scrim == 0 && !r.armed && r.book == nil)
        for s in r.spines { #expect(s.rise == 0 && s.lean == 0 && s.offsetX == 0 && s.scale == 1 && s.turn == 0 && s.opacity == 1 && !s.isActive) }
        #expect(r.spines.count == 7)
    }

    @Test func aBookWithoutAPhaseOrAPhaseWithoutABookIsResting() {
        #expect(f(.dragging, book: 99, drag: 50).phase == .resting)
        #expect(f(.dragging, book: -1, drag: 50).phase == .resting)
        #expect(ShelfTimeline.frame(layout: L, phase: .open, book: nil, time: 1).phase == .resting)
        #expect(f(.resting).phase == .resting)
    }

    @Test func draggingUsesTheRubberBand() {
        for d in [0.0, 10, 40, 90, 200, 600] {
            let fr = f(.dragging, drag: d)
            #expect(abs(fr.spines[3].rise - ShelfResistance.rise(forDrag: d, height: L.spines[3].height)) < 1e-12)
            #expect(fr.drag == d)
        }
    }

    @Test func draggingBelowZeroOrBadDoesNotMove() {
        #expect(f(.dragging, drag: -30).spines[3].rise == 0)
        #expect(f(.dragging, drag: .nan).spines[3].rise == 0)
    }

    @Test func armedAtTheCommitDistanceAndPullProgress() {
        let h = L.spines[3].height, c = ShelfResistance.commitDistance(height: h)
        #expect(!f(.dragging, drag: c - 0.01).armed)
        #expect(f(.dragging, drag: c).armed)
        #expect(abs(f(.dragging, drag: c / 2).pullProgress - 0.5) < 1e-12)
        #expect(f(.dragging, drag: c * 3).pullProgress == 1)
        #expect(f(.lifting, 0.1).pullProgress == 0)
    }

    @Test func onlyThePulledBookIsActive() {
        let fr = f(.dragging, drag: 60)
        #expect(fr.spines.filter(\.isActive).map(\.index) == [3])
        #expect(fr.spines[3].lean == 0)
    }

    @Test func neighboursLeanWhileTheBookRises() {
        let fr = f(.dragging, drag: 100)
        #expect(fr.spines[2].lean > 5 && fr.spines[4].lean < -5)
        #expect(fr.spines[2].pivotsTrailing && !fr.spines[4].pivotsTrailing)
        #expect(fr.spines[2].lean == ShelfLean.angles(layout: L, lifted: 3, rise: fr.spines[3].rise)[2])
    }

    @Test func liftingStartsAtTheReleaseAndEndsOnTheStage() {
        let start = f(.lifting, 0, rise0: 40)
        #expect(abs(start.spines[3].rise - 40) < 1e-12 && start.spines[3].offsetX == 0 && start.spines[3].scale == 1)
        let end = f(.lifting, ShelfTimeline.liftDuration, rise0: 40)
        #expect(abs(end.spines[3].rise - L.liftedRise(3)) < 1e-9)
        #expect(abs(end.spines[3].offsetX - (ShelfLayout.stage.x - L.spines[3].centerX)) < 1e-9)
        #expect(abs(end.spines[3].scale - ShelfLayout.stageScale) < 1e-12)
    }

    @Test func liftingRisesMonotonicallyAndEasesOut() {
        var prev = 40.0, prevStep = Double.infinity
        for i in 1...45 {
            let r = f(.lifting, Double(i) * 0.01, rise0: 40).spines[3].rise
            #expect(r >= prev - 1e-12)
            #expect(r - prev <= prevStep + 1e-9)
            prevStep = r - prev; prev = r
        }
    }

    @Test func neighboursStayLeaningWhileLifted() {
        let end = f(.lifting, ShelfTimeline.liftDuration, rise0: 40)
        #expect(end.spines[2].lean > 8 && end.spines[4].lean < -8)
    }

    @Test func turningRotatesNinetyDegreesWithEasing() {
        #expect(f(.turning, 0).spines[3].turn == 0)
        #expect(abs(f(.turning, ShelfTimeline.turnDuration).spines[3].turn - 90) < 1e-12)
        #expect(abs(f(.turning, ShelfTimeline.turnDuration / 2).spines[3].turn - 45) < 1e-9)
        var prev = 0.0
        for i in 0...50 {
            let t = f(.turning, Double(i) * 0.01).spines[3].turn
            #expect(t >= prev - 1e-12 && t <= 90 + 1e-12)
            prev = t
        }
    }

    @Test func turningHoldsTheStagePose() {
        let a = f(.turning, 0.2).spines[3], b = f(.turning, 0.4).spines[3]
        #expect(a.rise == b.rise && a.offsetX == b.offsetX && a.scale == b.scale)
        #expect(abs(a.rise - L.liftedRise(3)) < 1e-9)
    }

    @Test func openGrowsTheCoverIntoTheCard() {
        let a = f(.open, 0), z = f(.open, 0.5), later = f(.open, 20)
        #expect(a.card!.progress == 0 && z.card!.progress == 1 && later.card!.progress == 1)
        #expect(a.card!.rect == L.coverRect(3))
        #expect(z.card!.rect == ShelfLayout.cardRect)
        #expect(a.card!.contentOpacity == 0 && z.card!.contentOpacity == 1)
        #expect(a.card!.coverOpacity == 1 && z.card!.coverOpacity == 0)
        #expect(a.card!.cornerRadius < z.card!.cornerRadius)
        #expect(a.scrim == 0 && z.scrim == ShelfTimeline.maxScrim)
        #expect(z.spines[3].opacity == 0)
    }

    @Test func coverAtTurnNinetyMatchesTheCardAtZero() {
        for b in 0..<7 {
            let turned = ShelfTimeline.frame(layout: L, phase: .turning, book: b, time: ShelfTimeline.turnDuration)
            let card = ShelfTimeline.frame(layout: L, phase: .open, book: b, time: 0)
            let s = turned.spines[b]
            let coverW = L.spines[b].coverWidth * s.scale, coverH = L.spines[b].height * s.scale
            #expect(abs(coverW - card.card!.rect.width) < 1e-9 && abs(coverH - card.card!.rect.height) < 1e-9)
            let centreY = ShelfLayout.plankTop - L.spines[b].height / 2 - s.rise
            #expect(abs(centreY - card.card!.rect.midY) < 1e-9)
            #expect(abs(L.spines[b].centerX + s.offsetX - card.card!.rect.midX) < 1e-9)
        }
    }

    @Test func cardGrowsMonotonically() {
        var prev = 0.0
        for i in 0...50 {
            let p = f(.open, Double(i) * 0.01).card!.progress
            #expect(p >= prev - 1e-12)
            prev = p
        }
    }

    @Test func closingShrinksTheCardThenTurnsBackThenSlidesDown() {
        let t0 = f(.returning, 0, kind: .card), t1 = f(.returning, 0.4, kind: .card)
        #expect(t0.card!.progress == 1 && t0.card!.rect == ShelfLayout.cardRect)
        #expect(t1.card == nil && abs(t1.spines[3].turn - 90) < 1e-9)
        let t2 = f(.returning, 0.4 + 0.45, kind: .card)
        #expect(abs(t2.spines[3].turn) < 1e-9 && abs(t2.spines[3].rise - L.liftedRise(3)) < 1e-9)
        let end = f(.returning, ShelfTimeline.cardReturnDuration, kind: .card)
        #expect(abs(end.spines[3].rise) < 1e-9 && abs(end.spines[3].offsetX) < 1e-9 && abs(end.spines[3].scale - 1) < 1e-9)
        #expect(end.spines.allSatisfy { abs($0.lean) < 1e-9 })
    }

    @Test func cardShrinkIsContinuousWithTheTurnBack() {
        let before = f(.returning, 0.4 - 1e-9, kind: .card).card!
        #expect(before.progress < 1e-6)
        #expect(abs(before.rect.width - L.coverRect(3).width) < 1e-3)
    }

    @Test func slideDownGoesDownMonotonicallyAndNeighboursStraighten() {
        var prevRise = Double.infinity, prevLean = Double.infinity
        for i in 0...55 {
            let fr = f(.returning, 0.85 + Double(i) * 0.01, kind: .card)
            #expect(fr.spines[3].rise <= prevRise + 1e-9)
            #expect(abs(fr.spines[2].lean) <= prevLean + 1e-9)
            prevRise = fr.spines[3].rise; prevLean = abs(fr.spines[2].lean)
        }
    }

    @Test func springBackStartsAtTheReleaseAndSettlesHome() {
        #expect(abs(f(.returning, 0, rise0: 30, kind: .springBack).spines[3].rise - 30) < 1e-9)
        #expect(f(.returning, ShelfTimeline.springBackDuration, rise0: 30, kind: .springBack).spines[3].rise == 0)
        #expect(f(.returning, 3, rise0: 30, kind: .springBack).spines[3].rise == 0)
        for i in 0...55 { #expect(f(.returning, Double(i) * 0.01, rise0: 30, kind: .springBack).spines[3].rise >= 0) }
    }

    @Test func springBackDoesNotMoveSidewaysOrTurn() {
        let s = f(.returning, 0.2, rise0: 30, kind: .springBack).spines[3]
        #expect(s.offsetX == 0 && s.scale == 1 && s.turn == 0 && s.opacity == 1)
    }

    @Test func springBackIsMostlyHomeByTheEnd() {
        #expect(f(.returning, 0.5, rise0: 30, kind: .springBack).spines[3].rise < 0.8)
    }

    @Test func fadeReturnCrossfadesWithoutMoving() {
        let a = f(.returning, 0, kind: .fade, reduce: true), m = f(.returning, 0.125, kind: .fade, reduce: true)
        let z = f(.returning, 0.25, kind: .fade, reduce: true)
        #expect(a.card!.opacity == 1 && abs(m.card!.opacity - 0.5) < 1e-9 && z.card!.opacity == 0)
        #expect(a.spines.allSatisfy { $0.rise == 0 && $0.turn == 0 && $0.scale == 1 && $0.lean == 0 })
    }

    @Test func reduceMotionOpenIsAFadeWithNo3D() {
        for t in stride(from: 0.0, through: 1, by: 0.05) {
            let fr = f(.open, t, reduce: true)
            #expect(fr.spines.allSatisfy { $0.turn == 0 && $0.rise == 0 && $0.scale == 1 && $0.offsetX == 0 && $0.lean == 0 && $0.opacity == 1 })
            #expect(fr.card!.progress == 1 && fr.card!.rect == ShelfLayout.cardRect)
        }
        #expect(f(.open, 0, reduce: true).card!.opacity == 0)
        #expect(f(.open, 0.25, reduce: true).card!.opacity == 1)
    }

    @Test func seatingWobblesTheNeighboursThenSettles() {
        let a = f(.seating, 0.05), z = f(.seating, 0.4)
        #expect(a.spines[3].rise == 0 && a.card == nil)
        #expect(abs(a.spines[2].lean) > 0.1 && abs(a.spines[4].lean) > 0.1)
        #expect(abs(a.spines[2].lean) > abs(a.spines[1].lean))
        #expect(abs(z.spines[2].lean) < 0.06)
        #expect(a.spines[2].lean * a.spines[4].lean < 0)
    }

    @Test func seatingUnderReduceMotionHasNoWobble() {
        #expect(f(.seating, 0.05, reduce: true).spines.allSatisfy { $0.lean == 0 })
    }

    @Test func timesBeforeZeroAndBadTimesAreZero() {
        #expect(f(.turning, -3).spines[3].turn == 0)
        #expect(f(.turning, .nan).spines[3].turn == 0)
        #expect(f(.open, -1).card!.progress == 0)
    }

    @Test func durationsPerPhase() {
        #expect(ShelfTimeline.duration(.resting, kind: .card, reduceMotion: false) == nil)
        #expect(ShelfTimeline.duration(.dragging, kind: .card, reduceMotion: false) == nil)
        #expect(ShelfTimeline.duration(.open, kind: .card, reduceMotion: false) == nil)
        #expect(ShelfTimeline.duration(.lifting, kind: .card, reduceMotion: false) == 0.45)
        #expect(ShelfTimeline.duration(.turning, kind: .card, reduceMotion: false) == 0.5)
        #expect(abs(ShelfTimeline.duration(.returning, kind: .card, reduceMotion: false)! - 1.4) < 1e-12)
        #expect(ShelfTimeline.duration(.returning, kind: .springBack, reduceMotion: false) == 0.55)
        #expect(ShelfTimeline.duration(.returning, kind: .fade, reduceMotion: true) == 0.25)
        #expect(ShelfTimeline.duration(.seating, kind: .card, reduceMotion: false) == 0.4)
        #expect(ShelfTimeline.duration(.seating, kind: .card, reduceMotion: true) == 0.12)
    }

    @Test func turnLayoutKeepsTheBookCentred() {
        for deg in stride(from: 0.0, through: 90, by: 7.5) {
            let t = ShelfTimeline.turnLayout(spineWidth: 36, coverWidth: 100, degrees: deg)
            // spine to the left of the hinge, cover to the right: the pair is centred on 0
            #expect(abs((t.hinge - t.spine) + (t.hinge + t.cover)) < 1e-9)
        }
        let a = ShelfTimeline.turnLayout(spineWidth: 36, coverWidth: 100, degrees: 0)
        #expect(a.spine == 36 && abs(a.cover) < 1e-12)
        let z = ShelfTimeline.turnLayout(spineWidth: 36, coverWidth: 100, degrees: 90)
        #expect(abs(z.spine) < 1e-9 && abs(z.cover - 100) < 1e-9)
        #expect(ShelfTimeline.turnLayout(spineWidth: 36, coverWidth: 100, degrees: 400).cover > 99.9)
        #expect(ShelfTimeline.turnLayout(spineWidth: 36, coverWidth: 100, degrees: .nan).spine == 36)
    }

    @Test func framesAreFiniteEverywhere() {
        for phase in ShelfPhase.allCases {
            for kind in [ShelfReturnKind.card, .springBack, .fade] {
                for t in stride(from: -0.1, through: 2, by: 0.07) {
                    let fr = f(phase, t, drag: 70, rise0: 35, kind: kind, reduce: kind == .fade)
                    for s in fr.spines {
                        #expect(s.rise.isFinite && s.lean.isFinite && s.offsetX.isFinite && s.scale.isFinite && s.turn.isFinite && s.opacity.isFinite)
                    }
                }
            }
        }
    }
}
