import Foundation
import Testing
@testable import GlassPourCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

@Suite struct GeometryTests {
    @Test func seatsAndPage() {
        #expect(GlassPourLayout.pitch == 64)
        #expect(GlassPourLayout.dropCenter == Vec2(114, 36))
        #expect(GlassPourLayout.restCenter(0) == Vec2(114, 105))
        #expect(GlassPourLayout.restCenter(3) == Vec2(114, 297))
        #expect(GlassPourLayout.height(count: 4) == 340)
        #expect(GlassPourLayout.height(count: 0) == 84)
        #expect(GlassPourLayout.pageWidth == 390 && GlassPourLayout.pageHeight == 844)
        #expect(GlassPourLayout.pageOrigin == Vec2(81, 300))
        let bottom = GlassPourLayout.pageOrigin.y + GlassPourLayout.height(count: 4)
        #expect(bottom < GlassPourLayout.pageHeight - 40)
        // At rest the gap is wider than the goo can bridge, so the pills read as separate glass.
        #expect(GlassPourLayout.rowGap > GlassPourLayout.breakGap)
    }

    @Test func neckNarrowsAndPinchesOff() {
        #expect(GlassPourLayout.neckWidth(gap: -8) == GlassPourLayout.maxNeck)
        #expect(GlassPourLayout.neckWidth(gap: 0) == GlassPourLayout.maxNeck)
        #expect(GlassPourLayout.neckWidth(gap: GlassPourLayout.breakGap) == 0)
        #expect(GlassPourLayout.neckWidth(gap: 40) == 0)
        #expect(near(GlassPourLayout.pinch(gap: 0), 0) && near(GlassPourLayout.pinch(gap: 14), 1))
        let widths = stride(from: -2.0, through: 14, by: 0.25).map { GlassPourLayout.neckWidth(gap: $0) }
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 >= $1 - 1e-12 })
        let upper = GlassPourBlob(center: Vec2(114, 40), halfWidth: 30, radius: 30)
        func lower(_ gap: Double) -> GlassPourBlob {
            GlassPourBlob(center: Vec2(114, 70 + gap + 20), halfWidth: 80, radius: 20)
        }
        let touching = GlassPourLayout.neck(upper: upper, lower: lower(0))
        #expect(touching?.width == 40 && touching?.waist == 40)
        let stretched = GlassPourLayout.neck(upper: upper, lower: lower(6))
        #expect(stretched != nil && stretched!.waist < stretched!.width)
        #expect(GlassPourLayout.neck(upper: upper, lower: lower(11)) == nil)
        let polygon = touching!.polygon
        #expect(polygon.count == 6)
        #expect(near(polygon[0].x + polygon[5].x, 228) && near(polygon[1].x + polygon[4].x, 228))
        #expect(polygon[0].y == 40 && polygon[2].y == 90)
    }

    @Test func restPillsAreSeparateAndTheDropIsACircle() {
        let drop = GlassPourLayout.dropBlob(scale: 1)
        #expect(drop.halfWidth == drop.radius && drop.radius == 30)
        let rows = (0..<4).map { GlassPourLayout.pillBlob(center: GlassPourLayout.restCenter($0), scale: 1) }
        #expect(GlassPourLayout.necks(drop: drop, rows: rows).isEmpty)
        let born = GlassPourLayout.pillBlob(center: GlassPourLayout.dropCenter, scale: GlassPourTuning.minScale)
        #expect(!GlassPourLayout.necks(drop: drop, rows: [born]).isEmpty)
    }

    @Test func hitTestingTheDropAndACapsule() {
        #expect(GlassPourLayout.containsDrop(GlassPourLayout.dropCenter, scale: 1))
        let insideSlop = Vec2(GlassPourLayout.dropCenter.x + GlassPourLayout.dropRadius + 3, GlassPourLayout.dropCenter.y)
        let outside = Vec2(GlassPourLayout.dropCenter.x + GlassPourLayout.dropRadius + 6, GlassPourLayout.dropCenter.y)
        #expect(GlassPourLayout.containsDrop(insideSlop, scale: 1))
        #expect(!GlassPourLayout.containsDrop(outside, scale: 1))
        let seat = GlassPourLayout.restCenter(1)
        #expect(GlassPourLayout.containsPill(seat, center: seat, scale: 1))
        #expect(GlassPourLayout.containsPill(Vec2(seat.x + 90, seat.y), center: seat, scale: 1))
        #expect(!GlassPourLayout.containsPill(Vec2(seat.x + 100, seat.y), center: seat, scale: 1))
        // The corner of the bounding box is outside the semicircular end.
        #expect(!GlassPourLayout.containsPill(Vec2(seat.x + 98, seat.y + 25), center: seat, scale: 1))
        let highlight = GlassPourLayout.dropHighlight(scale: 1)
        #expect(highlight.center.x < GlassPourLayout.dropCenter.x)
        #expect(highlight.center.y < GlassPourLayout.dropCenter.y)
        #expect(near(highlight.radius, 12.6))
    }
}
