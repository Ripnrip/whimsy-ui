import Testing
import Foundation
@testable import StarJarCore

@Suite("StarJarGeometry") struct GeometryTests {
    typealias G = StarJarGeometry
    @Test(arguments: [(150.0, 212.0), (150, 300), (60, 212), (240, 212), (150, 64), (150, 40), (110, 64), (190, 64), (150, 110)])
    func insidePoints(_ p: (Double, Double)) {
        #expect(G.contains(p.0, p.1))
        #expect(G.distance(p.0, p.1) < 0)
    }
    @Test(arguments: [(5.0, 212.0), (295, 212), (150, 335), (150, 25), (60, 60), (240, 60), (35, 100), (265, 330), (20, 330)])
    func outsidePoints(_ p: (Double, Double)) {
        #expect(!G.contains(p.0, p.1))
        #expect(G.distance(p.0, p.1) > 0)
    }
    @Test func distanceIsExactOnFlatWalls() {
        #expect(abs(G.distance(150, 212) - -118) < 1e-9)     // body centre: nearest is top/bottom (half 118)
        #expect(abs(G.distance(150, 330) - 0) < 1e-9)        // bottom wall
        #expect(abs(G.distance(30, 212) - 0) < 1e-9)         // left wall
        #expect(abs(G.distance(150, 20) - (10)) < 1e-9)      // above neck top (30)
    }
    @Test func roundedCornerIsRound() {
        // A point on the diagonal of the bottom-right corner, 54 from the arc centre, sits on the wall.
        let cx = 150 + 120 - 54.0, cy = 212 + 118 - 54.0
        let px = cx + 54 / 2.0.squareRoot(), py = cy + 54 / 2.0.squareRoot()
        #expect(abs(G.distance(px, py)) < 1e-9)
        #expect(G.distance(270, 330) > 10)                   // the square corner is outside
    }
    @Test(arguments: [(30.0, 212.0, -1.0, 0.0), (270, 212, 1, 0), (150, 330, 0, 1), (94, 70, -1, 0), (206, 70, 1, 0), (150, 30, 0, -1)])
    func normalsPointOutward(_ c: (Double, Double, Double, Double)) {
        let n = G.normal(c.0, c.1)
        #expect(abs(n.x - c.2) < 1e-6 && abs(n.y - c.3) < 1e-6)
    }
    @Test func normalsAreUnitLength() {
        for i in 0..<30 { for j in 0..<34 {
            let n = G.normal(Double(i) * 10 + 5, Double(j) * 10 + 5)
            #expect(abs((n.x * n.x + n.y * n.y).squareRoot() - 1) < 1e-9)
        } }
    }
    @Test func neckIsNarrowerThanBody() {
        #expect(G.neck.width < G.body.width)
        #expect(G.neck.maxY > G.body.y)          // they overlap, so the union is one cavity
        #expect(G.contains(150, G.body.y + 1))
    }
    @Test func corkCapsTheNeck() {
        #expect(G.cork.x >= G.neck.x && G.cork.maxX <= G.neck.maxX)   // a plug inside the mouth
        #expect(G.cork.maxY > G.neck.y)
        #expect(G.hitsJar(G.cork.midX, G.cork.midY))
        #expect(!G.contains(G.cork.midX, G.cork.y + 2))
    }
    @Test func doneChipIsOffTheJar() {
        let c = G.doneChip
        #expect(G.hitsDone(c.midX, c.midY))
        #expect(!G.hitsJar(c.midX, c.midY))
        #expect(c.maxX <= G.width && c.y >= 0)
    }
    @Test func nonFiniteIsOutside() {
        #expect(!G.contains(.nan, 100))
        #expect(!G.contains(100, .infinity))
    }
    @Test func jarFitsCanvas() {
        #expect(G.body.x >= 0 && G.body.maxX <= G.width && G.body.maxY <= G.height)
        #expect(G.cork.y >= 0)
    }
    @Test func rectHelpers() {
        let r = JarRect(x: 1, y: 2, width: 10, height: 20)
        #expect(r.maxX == 11 && r.maxY == 22 && r.midX == 6 && r.midY == 12)
        #expect(r.contains(1, 2) && r.contains(11, 22) && !r.contains(0.9, 5))
    }
}
