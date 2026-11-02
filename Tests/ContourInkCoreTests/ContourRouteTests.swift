import Testing
import Foundation
@testable import ContourInkCore

@Suite struct RouteShapeTests {
    private let map = ContourMap.make()
    private var route: ContourRoute { ContourRoute.make(map: map) }

    @Test func oneWaypointPerRingThenThePeak() {
        let r = route
        #expect(r.waypoints.count == map.count + 1)
        #expect(r.waypoints.last == map.peak)
        #expect(r.points.count == map.count * ContourRoute.subdivisions + 1)
    }

    @Test func startsOnTheOutermostRing() {
        let r = route
        #expect(map.rings[0].distance(to: r.start) < 0.001)
        #expect(!map.rings[1].contains(r.start))
    }

    @Test func endsExactlyAtThePeak() {
        let r = route
        #expect(r.end == map.peak)
        #expect(r.point(at: 1) == map.peak)
    }

    @Test func eachWaypointSitsOnItsRing() {
        let r = route
        for k in 0..<map.count { #expect(map.rings[k].distance(to: r.waypoints[k]) < 0.001) }
    }

    @Test func theSmoothTrailPassesThroughEveryWaypoint() {
        let r = route
        for i in 0..<r.waypoints.count - 1 {
            #expect(r.points[i * ContourRoute.subdivisions].distance(to: r.waypoints[i]) < 1e-12)
        }
    }

    @Test func crossesEveryRingOnTheWayIn() {
        let r = route
        for k in 0..<map.count {
            #expect(r.points.contains { map.rings[k].contains($0) }, "never inside ring \(k)")
            if k > 0 { #expect(r.points.contains { !map.rings[k].contains($0) }, "never outside ring \(k)") }
        }
    }

    @Test func endsInsideEveryRingAndStartsInsideAtMostTheFirst() {
        let r = route
        #expect(map.rings.filter { $0.contains(r.end) }.count == map.count)
        #expect(map.rings.filter { $0.contains(r.start) }.count <= 1)
    }

    @Test func staysOnTheSheet() {
        for n in [3, 6, 7, 12] {
            let m = ContourMap.make(rings: n)
            for p in ContourRoute.make(map: m).points { #expect(abs(p.x) < 0.5 && abs(p.y) < 0.5) }
        }
    }

    @Test func isLongerThanAStraightWalkBecauseOfTheSwitchbacks() {
        let r = route
        #expect(r.length > r.start.distance(to: r.end) * 1.2)
    }

    @Test func deepensOverallAsItClimbs() {
        let r = route
        func depth(_ p: Vec2) -> Int { map.rings.filter { $0.contains(p) }.count }
        let samples = (0...20).map { depth(r.point(at: Double($0) / 20)) }
        #expect(samples.last == map.count)
        #expect(samples[0] <= 1)
        #expect(samples[10] > samples[0])
        #expect(zip(samples, samples.dropFirst(5)).allSatisfy { $0 <= $1 + 2 })
    }

    @Test func isDeterministicAndFollowsTheSeed() {
        #expect(ContourRoute.make(map: map) == ContourRoute.make(map: map))
        let other = ContourRoute.make(map: ContourMap.make(rings: 7, seed: 4))
        #expect(other != route)
        #expect(other.start != route.start)
    }

    @Test func startAngleJitterIsSmall() {
        for s in 0..<30 {
            let m = ContourMap.make(rings: 7, seed: UInt32(s) &+ 1000)
            let r = ContourRoute.make(map: m)
            let a = atan2(r.start.y - m.rings[0].center.y, r.start.x - m.rings[0].center.x)
            let wanted = ContourRoute.baseAngle
            #expect(abs(a - wanted) < 0.21, "seed \(s)")
        }
    }

    @Test func worksForEveryRingCount() {
        for n in 3...12 {
            let m = ContourMap.make(rings: n)
            let r = ContourRoute.make(map: m)
            #expect(r.waypoints.count == n + 1)
            #expect(r.end == m.peak && r.length > 0)
        }
    }
}

@Suite struct RoutePositionTests {
    private let route = ContourRoute.make(map: ContourMap.make())

    @Test func lengthIsTheSumOfItsSegments() {
        var sum = 0.0
        for i in 1..<route.points.count { sum += route.points[i].distance(to: route.points[i - 1]) }
        #expect(abs(sum - route.length) < 1e-12)
        #expect(route.cumulative[0] == 0)
        for i in 1..<route.cumulative.count { #expect(route.cumulative[i] > route.cumulative[i - 1]) }
    }

    @Test func pointAtZeroIsTheStartAndAtOneTheEnd() {
        #expect(route.point(at: 0) == route.start)
        #expect(route.point(at: 1) == route.end)
    }

    @Test func pointAtClampsAndSurvivesBadInput() {
        #expect(route.point(at: -1) == route.start)
        #expect(route.point(at: 9) == route.end)
        #expect(route.point(at: .nan) == route.start)
        #expect(route.point(at: .infinity) == route.end)
        #expect(route.point(at: -.infinity) == route.start)
    }

    @Test func pointAtHitsTheStoredPoints() {
        for i in stride(from: 0, to: route.points.count, by: 6) {
            #expect(route.point(at: route.cumulative[i] / route.length).distance(to: route.points[i]) < 1e-9)
        }
    }

    @Test func theDotMovesAtConstantSpeedPerArcFraction() {
        let d = 1.0 / 300
        for i in 0..<300 {
            let a = route.point(at: Double(i) * d), b = route.point(at: Double(i + 1) * d)
            #expect(a.distance(to: b) <= route.length * d + 1e-9)
            #expect(a.distance(to: b) >= route.length * d * 0.5)
        }
    }

    @Test func halfTheFractionIsHalfTheWalkedLength() {
        // the arc length up to point(at: 0.5) equals half the total
        var walked = 0.0
        let half = route.point(at: 0.5)
        var i = 0
        while route.cumulative[i + 1] < route.length / 2 { walked = route.cumulative[i + 1]; i += 1 }
        walked += route.points[i].distance(to: half)
        #expect(abs(walked - route.length / 2) < 1e-9)
    }

    @Test func catmullRomHitsItsControlPointsAtTheEnds() {
        let a = Vec2(0, 0), b = Vec2(1, 0), c = Vec2(2, 1), d = Vec2(3, 1)
        #expect(ContourRoute.catmullRom(a, b, c, d, 0) == b)
        #expect(ContourRoute.catmullRom(a, b, c, d, 1) == c)
        let mid = ContourRoute.catmullRom(a, b, c, d, 0.5)
        #expect(mid.x > 1 && mid.x < 2)
    }
}
