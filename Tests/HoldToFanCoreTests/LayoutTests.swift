import Testing
import Foundation
@testable import HoldToFanCore

@Suite("Layout") struct LayoutTests {
    typealias L = HoldToFanLayout

    @Test(arguments: [3, 4, 5])
    func anglesAreEvenAndInUpperLeft(_ n: Int) {
        let a = L.angles(count: n)
        #expect(a.count == n)
        #expect(abs(a.first! - L.startAngle) < 1e-12)
        #expect(abs(a.last! - (L.startAngle - L.arcSpan)) < 1e-12)
        if n > 2 {
            let step = a[1] - a[0]
            for i in 1..<n { #expect(abs((a[i] - a[i - 1]) - step) < 1e-12) }
        }
        // Every angle sits between up (−π/2) and left (−π), inclusive.
        for θ in a {
            #expect(θ <= L.startAngle + 1e-12)
            #expect(θ >= L.startAngle - L.arcSpan - 1e-12)
        }
    }

    @Test func openPositionsSitOnTheArc() {
        for n in 3...5 {
            for i in 0..<n {
                let p = L.openPosition(of: i, count: n)
                #expect(abs(L.distance(of: p) - L.arcRadius) < 1e-9)
                #expect(abs(L.angleDelta(L.angle(of: p), L.angles(count: n)[i])) < 1e-9)
            }
        }
    }

    @Test func progressInterpolatesFromFabToArc() {
        let a = L.position(of: 0, count: 4, progress: 0)
        let b = L.position(of: 0, count: 4, progress: 1)
        let m = L.position(of: 0, count: 4, progress: 0.5)
        #expect(a == L.fab)
        #expect(abs(L.distance(of: b) - L.arcRadius) < 1e-9)
        #expect(abs(L.distance(of: m) - L.arcRadius * 0.5) < 1e-9)
    }

    @Test func angleDeltaIsShortestSigned() {
        #expect(abs(L.angleDelta(0, 0)) < 1e-12)
        #expect(abs(L.angleDelta(.pi, -.pi)) < 1e-12)
        #expect(L.angleDelta(0.1, -0.1) == 0.2)
        #expect(abs(L.angleDelta(.pi - 0.1, -.pi + 0.1) + 0.2) < 1e-12)
    }

    @Test(arguments: [(-2, 3), (0, 3), (2, 3), (6, 5), (100, 5)])
    func countIsClamped(_ c: (Int, Int)) {
        #expect(L.clampedCount(c.0) == c.1)
        #expect(HoldToFanModel(count: c.0).count == c.1)
    }

    @Test func fabAndArcFitCanvas() {
        #expect(L.fab.x + L.fabRadius < L.width)
        #expect(L.fab.y + L.fabRadius < L.height)
        for n in 3...5 {
            for i in 0..<n {
                let p = L.openPosition(of: i, count: n)
                #expect(p.x > -40 && p.x < L.width + 40)
                #expect(p.y > -40 && p.y < L.height + 40)
            }
        }
    }
}
