import Testing
import Foundation
@testable import ShutterRevealCore

/// Points on a grid inside the covered disc (excluding the exact centre, where every tip meets).
private func discSamples(_ g: IrisGeometry, perAxis n: Int = 41) -> [Vec2] {
    var out: [Vec2] = []
    for iy in 0..<n {
        for ix in 0..<n {
            let p = g.center + Vec2(Double(ix) / Double(n - 1) * 2 - 1, Double(iy) / Double(n - 1) * 2 - 1) * g.radius
            if p.distance(to: g.center) <= g.radius && p.distance(to: g.center) > 1e-6 { out.append(p) }
        }
    }
    // Also the rim, where an "almost open" iris would first show a gap.
    for k in 0..<180 { out.append(g.center + Vec2.unit(Double(k) / 180 * 2 * .pi) * g.radius) }
    return out
}

@Suite("Iris geometry")
struct IrisGeometryTests {
    @Test(arguments: [3, 5, 6, 8, 12])
    func closedCoversEverything(blades: Int) {
        let g = IrisGeometry(bladeCount: blades, width: 320, height: 420)
        let samples = discSamples(g)
        #expect(samples.allSatisfy { g.isCovered($0, progress: 0) })
        #expect(g.coveredFraction(progress: 0) == 1)
    }

    @Test(arguments: [3, 5, 6, 8, 12])
    func openClearsEverything(blades: Int) {
        let g = IrisGeometry(bladeCount: blades, width: 320, height: 420)
        let samples = discSamples(g)
        #expect(samples.allSatisfy { !g.isCovered($0, progress: 1) })
        #expect(g.coveredFraction(progress: 1) == 0)
    }

    @Test(arguments: [0.15, 0.4, 0.6, 0.85])
    func midwayBladesTileTheOutsideExactly(progress: Double) {
        let g = IrisGeometry(bladeCount: 6, width: 300, height: 300)
        for p in discSamples(g, perAxis: 37) {
            let covering = g.coveringBlades(p, progress: progress)
            let inAperture = g.isInsideAperture(p, progress: progress)
            // Every sample is either in the aperture or under a blade, never both...
            #expect(inAperture != !covering.isEmpty)
            // ...and never under more than two blades (only exactly on a seam).
            #expect(covering.count <= 2)
        }
    }

    @Test func coverageDecreasesMonotonically() {
        let g = IrisGeometry(bladeCount: 6, width: 320, height: 420)
        let fractions = stride(from: 0.0, through: 1.0, by: 0.1).map { g.coveredFraction(progress: $0) }
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(fractions.first == 1 && fractions.last == 0)
    }

    @Test func closedTipsMeetAtTheCentre() {
        let g = IrisGeometry(bladeCount: 6, center: Vec2(10, 20), radius: 100)
        #expect(g.blades(progress: 0).allSatisfy { $0.apex.distance(to: g.center) < 1e-12 })
        #expect(g.apertureVertices(progress: 0).allSatisfy { $0 == g.center })
    }

    @Test func openApertureInscribesTheRegion() {
        let g = IrisGeometry(bladeCount: 6, radius: 100)
        #expect(g.apothem(progress: 1) >= g.radius)
        #expect(abs(g.circumradius(progress: 1) - 104 / cos(.pi / 6)) < 1e-9)
        // Overshoot opens wider; negative progress clamps to closed.
        #expect(g.apothem(progress: 1.1) > g.apothem(progress: 1))
        #expect(g.apothem(progress: -0.2) == 0)
        #expect(g.apothem(progress: .nan) == 0)
    }

    @Test func rotationAdvancesWithProgress() {
        let g = IrisGeometry(bladeCount: 6, radius: 100, twist: 0.9)
        #expect(g.rotation(progress: 0) == -.pi / 2)
        #expect(abs(g.rotation(progress: 1) - g.rotation(progress: 0) - 0.9) < 1e-12)
        let a = g.blade(0, progress: 0.3).angle, b = g.blade(0, progress: 0.6).angle
        #expect(abs((b - a) - 0.27) < 1e-9)
    }

    @Test func bladesAreConvexCounterClockwiseKites() {
        let g = IrisGeometry(bladeCount: 7, radius: 150)
        for blade in g.blades(progress: 0.5) {
            let poly = blade.polygon
            #expect(poly.count == 4)
            for i in poly.indices {
                let a = poly[i], b = poly[(i + 1) % 4], c = poly[(i + 2) % 4]
                #expect((b - a).cross(c - b) > 0)
            }
            #expect(abs(blade.leading.length - 1) < 1e-12 && abs(blade.trailing.length - 1) < 1e-12)
            // The exterior angle between the seams is 2π/N.
            let angle = atan2(blade.trailing.cross(blade.leading), blade.trailing.dot(blade.leading))
            #expect(abs(angle - 2 * .pi / 7) < 1e-9)
        }
    }

    @Test func apertureEdgeEndsAtTheNextTip() {
        let g = IrisGeometry(bladeCount: 6, radius: 100)
        let blades = g.blades(progress: 0.5)
        for (i, blade) in blades.enumerated() {
            #expect(blade.edgeEnd.distance(to: blades[(i + 1) % blades.count].apex) < 1e-9)
        }
    }

    @Test func bladeCountIsClampedToThree() {
        #expect(IrisGeometry(bladeCount: 1, radius: 10).bladeCount == 3)
        #expect(IrisGeometry(bladeCount: 2, radius: 10).blades(progress: 0.5).count == 3)
    }

    @Test func rectangleConvenienceUsesHalfDiagonal() {
        let g = IrisGeometry(width: 300, height: 400)
        #expect(g.center == Vec2(150, 200))
        #expect(g.radius == 250)
    }

    @Test func rectangleCornersAreCoveredWhenClosedAndClearWhenOpen() {
        let g = IrisGeometry(width: 320, height: 420)
        let corners = [Vec2(0, 0), Vec2(320, 0), Vec2(0, 420), Vec2(320, 420)]
        #expect(corners.allSatisfy { g.isCovered($0, progress: 0) })
        #expect(corners.allSatisfy { !g.isCovered($0, progress: 1) })
    }
}
