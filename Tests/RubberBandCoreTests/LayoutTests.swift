import Testing
import Foundation
@testable import RubberBandCore

@Suite("Fan geometry") struct LayoutTests {
    @Test func fiveCardsOnABottomArc() {
        #expect(RubberBandLayout.count == 5)
        let centers = (0..<5).map { RubberBandLayout.restCenter($0) }
        // Middle card is the highest (smallest y). Outer cards fall toward the bottom edge.
        #expect(centers[2].y < centers[1].y && centers[1].y < centers[0].y)
        #expect(centers[2].y < centers[3].y && centers[3].y < centers[4].y)
        #expect(centers[0].x < centers[1].x && centers[1].x < centers[2].x)
        #expect(centers[2].x < centers[3].x && centers[3].x < centers[4].x)
    }

    @Test func theFanIsSymmetric() {
        for i in 0..<5 {
            let a = RubberBandLayout.restCenter(i)
            let b = RubberBandLayout.restCenter(4 - i)
            let mid = RubberBandLayout.width / 2
            #expect(abs((a.x - mid) + (b.x - mid)) < 1e-9)
            #expect(abs(a.y - b.y) < 1e-9)
            #expect(abs(RubberBandLayout.restRotation(i) + RubberBandLayout.restRotation(4 - i)) < 1e-9)
        }
        #expect(abs(RubberBandLayout.restRotation(2)) < 1e-12)
    }

    @Test func outerBottomsSitOnTheMarginAndEverythingIsOnCanvas() {
        let bottom = RubberBandLayout.restCenter(0).y + RubberBandLayout.cardHeight / 2
        #expect(abs(bottom - (RubberBandLayout.height - RubberBandLayout.bottomMargin)) < 1e-9)
        for i in 0..<5 {
            let c = RubberBandLayout.restCenter(i)
            #expect(c.x - RubberBandLayout.cardWidth / 2 > 8)
            #expect(c.x + RubberBandLayout.cardWidth / 2 < RubberBandLayout.width - 8)
            #expect(c.y - RubberBandLayout.cardHeight / 2 > 80)
            #expect(c.y + RubberBandLayout.cardHeight / 2 <= RubberBandLayout.height)
        }
    }

    @Test func neighboursOverlapLikeAHand() {
        let gap = RubberBandLayout.restCenter(2).x - RubberBandLayout.restCenter(1).x
        #expect(gap > 20)
        #expect(gap < RubberBandLayout.cardWidth - 10)
    }

    @Test func rotationsFanOutward() {
        let rots = (0..<5).map { RubberBandLayout.restRotation($0) }
        #expect(rots[0] < rots[1] && rots[1] < rots[2] && rots[2] < rots[3] && rots[3] < rots[4])
        #expect(rots[0] < -0.3 && rots[4] > 0.3)
    }

    @Test func hoverPicksTheNearestCardAndSticks() {
        let c2 = RubberBandLayout.restCenter(2)
        let c3 = RubberBandLayout.restCenter(3)
        #expect(RubberBandLayout.nearestIndex(to: c2, current: nil) == 2)
        let toward = Vec2(c2.x + 20, c2.y)
        #expect(RubberBandLayout.nearestIndex(to: toward, current: 2) == 2)
        let gap = c3.x - c2.x
        let past = Vec2(c2.x + (gap + RubberBandLayout.stickiness) / 2 + 4, c2.y)
        #expect(RubberBandLayout.nearestIndex(to: past, current: 2) == 3)
    }

    @Test func aPointAboveTheHandIsNotACard() {
        #expect(RubberBandLayout.nearestIndex(to: Vec2(195, 40), current: nil) == nil)
        #expect(!RubberBandLayout.handContains(Vec2(.nan, 10)))
    }

    @Test func theStageSitsAboveTheFan() {
        let stage = RubberBandLayout.stage
        let topOfFan = (0..<5).map { RubberBandLayout.restTop($0) }.min()!
        let presentedBottom = stage.y + RubberBandLayout.cardHeight / 2 * RubberBandLayout.presentedScale
        #expect(presentedBottom < topOfFan - 24)
        #expect(RubberBandLayout.presentedContains(stage))
        #expect(!RubberBandLayout.presentedContains(Vec2(20, 20)))
    }
}
