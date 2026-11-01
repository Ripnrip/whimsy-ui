import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct FigureSortTests {
    func node(_ lo: Vec3, _ hi: Vec3) -> SortNode { SortNode(min: lo, max: hi, centre: (lo + hi) * 0.5) }

    @Test func nearerBoxIsPaintedLast() {
        let back = node(Vec3(0, 0, 0), Vec3(2, 2, 2)), front = node(Vec3(10, 0, 0), Vec3(12, 2, 2))
        let o = FigureSorter.order([front, back], camera: FigureCamera(yaw: 0))
        #expect(o == [1, 0])
        let flipped = FigureSorter.order([front, back], camera: FigureCamera(yaw: 180))
        #expect(flipped == [0, 1])
    }

    @Test func aboveIsNearerFromAbove() {
        let low = node(Vec3(0, 0, 0), Vec3(4, 4, 4)), high = node(Vec3(0, 0, 10), Vec3(4, 4, 14))
        #expect(FigureSorter.order([high, low], camera: FigureCamera(yaw: 70)) == [1, 0])
    }

    @Test func resultIsAPermutation() {
        var nodes: [SortNode] = []
        for i in 0..<12 {
            let x = Double(i) * 3, y = Double(i % 3) * 5
            nodes.append(node(Vec3(x, y, 0), Vec3(x + 2, y + 2, 3)))
        }
        for yaw in stride(from: 0.0, to: 360, by: 40) {
            let o = FigureSorter.order(nodes, camera: FigureCamera(yaw: yaw))
            #expect(o.sorted() == Array(0..<12))
        }
    }

    @Test func overlappingBoxesFallBackToDepth() {
        let a = node(Vec3(0, 0, 0), Vec3(10, 10, 10)), b = node(Vec3(5, 5, 5), Vec3(15, 15, 15))
        let o = FigureSorter.order([a, b], camera: FigureCamera(yaw: 0))
        #expect(o == [0, 1])
    }

    @Test func cyclesStillTerminate() {
        // Three long bars chasing each other round a ring: each is in front of one and behind another along different axes.
        let a = node(Vec3(0, 0, 0), Vec3(10, 1, 1)), b = node(Vec3(9, 0, 2), Vec3(10, 10, 3)), c = node(Vec3(0, 9, 0), Vec3(10, 10, 4))
        let o = FigureSorter.order([a, b, c], camera: FigureCamera(yaw: 45))
        #expect(o.sorted() == [0, 1, 2])
    }

    @Test func frontHardwareIsOnTopOfTheCaseFromTheFrontAndBehindItFromTheBack() {
        var m = GumballModel()
        m.turntable.yaw = -32
        let front = FigureRenderer.render(m.scene(), camera: m.camera, style: m.style).order
        #expect(front.firstIndex(of: "crankKnob")! > front.firstIndex(of: "cabinet")!)
        #expect(front.firstIndex(of: "globe")! > front.firstIndex(of: "cabinet")!)
        m.turntable.yaw = 148
        let back = FigureRenderer.render(m.scene(), camera: m.camera, style: m.style).order
        #expect(back.firstIndex(of: "crankKnob")! < back.firstIndex(of: "cabinet")!)
    }

    @Test func theCaseIsAGhostUnderEverythingWhenSeeThrough() {
        var m = GumballModel()
        m.setSeeThrough(true)
        m.advance(by: 3)
        let f = m.frame()
        #expect(!f.order.contains("cabinet"))      // drawn as a ghost before the sorted nodes
        #expect(f.order.contains("wheel") && f.order.contains("chute"))
        let closed = GumballModel().frame()
        #expect(closed.order.contains("cabinet") && !closed.order.contains("wheel"))
    }

    @Test func shadowFallsToTheLowerLeftAtEveryYaw() {
        for yaw in stride(from: 0.0, to: 360, by: 30) {
            let cam = FigureCamera(yaw: yaw)
            let hull = FigureShadow.hull(of: [Vec3(0, 0, 0), Vec3(0, 0, 100)], camera: cam)
            #expect(hull.count == 2)
            // Height pushes the shadow left, and toward the viewer (down the screen).
            let left = hull[0], right = hull[1]
            #expect(abs((right.x - left.x) - 27.5) < 1e-6)
            #expect(left.y > right.y)
        }
    }

    @Test func convexHullOfASquareWithInteriorPoints() {
        let pts = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4), Vec2(2, 2), Vec2(1, 3)]
        let h = FigureShadow.convexHull(pts)
        #expect(h.count == 4)
        #expect(FigureShadow.contains(h, Vec2(2, 2)))
        #expect(!FigureShadow.contains(h, Vec2(5, 2)))
    }

    @Test func seeThroughAlphaScalesInteriorOnly() {
        var m = GumballModel()
        m.setSeeThrough(true)
        m.advance(by: 0.1)
        let half = m.xr
        #expect(half > 0 && half < 1)
        let items = m.frame().items.filter { $0.kind == .fill && $0.source == GumballLayout.ID.wheel }
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { abs($0.alpha - half) < 1e-9 })
    }

    @Test func gumballsInTheGlobeAreSortedFrontToBack() {
        let m = GumballModel()
        var s = m.scene()
        s.solids = []
        let cam = FigureCamera(yaw: 30)
        let f = FigureRenderer.render(s, camera: cam, style: m.style)
        // The ball discs come out far-to-near: highlights (white discs) appear in the order of increasing depth.
        let balls = s.globe!.balls.sorted { cam.depth($0.centre) < cam.depth($1.centre) }
        let discs = f.items.filter { $0.kind == .disc && $0.color == FigureColor(1, 1, 1) }
        #expect(discs.count >= balls.count)
        let firstBall = cam.project(balls[0].centre), lastBall = cam.project(balls[balls.count - 1].centre)
        let idx0 = discs.firstIndex { ($0.points[0] - firstBall).length < 3.2 }!
        let idx1 = discs.lastIndex { ($0.points[0] - lastBall).length < 3.2 }!
        #expect(idx0 < idx1)
    }
}
