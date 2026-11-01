import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct FigureInkTests {
    func frame(wobble: Double = 0.5, seed: UInt32 = 7, yaw: Double = -32) -> FigureFrame {
        var m = GumballModel()
        m.wobble = wobble
        m.turntable.yaw = yaw
        let s = m.scene()
        return FigureRenderer.render(s, camera: FigureCamera(yaw: yaw), style: FigureStyle(wobble: wobble, seed: seed))
    }

    @Test func wobbleIsDeterministic() {
        let a = frame(), b = frame()
        #expect(a.items == b.items)
        #expect(a.order == b.order)
    }

    @Test func aDifferentSeedWobblesDifferently() {
        #expect(frame(seed: 7).items != frame(seed: 8).items)
    }

    @Test func zeroWobbleGivesStraightEdges() {
        let f = frame(wobble: 0)
        let strokes = f.items.filter { $0.kind == .stroke && $0.points.count == 3 }
        #expect(strokes.count > 20)
        for s in strokes {
            let a = s.points[0], m = s.points[1], b = s.points[2]
            #expect(abs((m - a).cross(b - a)) < 1e-9)
        }
    }

    @Test func wobbleBendsEdgesOffTheLine() {
        let f = frame(wobble: 1)
        let bent = f.items.filter { $0.kind == .stroke && $0.points.count == 3 }.filter { abs(($0.points[1] - $0.points[0]).cross($0.points[2] - $0.points[0])) > 1e-6 }
        #expect(bent.count > 20)
    }

    @Test func displacementStaysWithinTheAmplitude() {
        let a = frame(wobble: 0), b = frame(wobble: 1)
        let fa = a.items.filter { $0.kind == .fill && $0.source > 0 && $0.source < 20 }
        let fb = b.items.filter { $0.kind == .fill && $0.source > 0 && $0.source < 20 }
        #expect(fa.count == fb.count && !fa.isEmpty)
        var worst = 0.0
        for (x, y) in zip(fa, fb) where x.points.count == y.points.count {
            for (p, q) in zip(x.points, y.points) { worst = max(worst, (p - q).length) }
        }
        #expect(worst > 0.05)
        #expect(worst < FigureStyle.vertexAmp * 2.0.squareRoot() + FigureStyle.edgeAmp + 1e-9)
    }

    @Test func vertexOffsetsDoNotChangeWhileTheFigureTurns() {
        let solid = FigureShapes.box(id: 9, part: "b", layer: .shell, palette: .metal, min: Vec3(-5, -5, 0), max: Vec3(5, 5, 10))
        let style = FigureStyle(wobble: 1, seed: 7)
        let key = FigureRenderer.solidKey(solid, style)
        var offsets: [[Vec2]] = []
        for yaw in [0.0, 45, 130, 300] {
            let cam = FigureCamera(yaw: yaw)
            let w = FigureRenderer.projected(solid, cam, key: key, wobble: 1)
            let p = FigureRenderer.projected(solid, cam, key: key, wobble: 0)
            offsets.append(zip(w, p).map { $0 - $1 })
        }
        for o in offsets.dropFirst() { for (a, b) in zip(o, offsets[0]) { #expect((a - b).length < 1e-9) } }
    }

    @Test func sharedEdgesBendTheSameFromEitherEnd() {
        let p = [Vec2(0, 0), Vec2(10, 3), Vec2(4, 9)]
        let m1 = FigureRenderer.midpoint(p, 0, 1, key: 5, wobble: 1)
        let m2 = FigureRenderer.midpoint(p, 1, 0, key: 5, wobble: 1)
        #expect((m1 - m2).length < 1e-12)
        #expect((m1 - Vec2(5, 1.5)).length <= FigureStyle.edgeAmp + 1e-9)
    }

    @Test func lineWeightsVaryASmallAmount() {
        let f = frame(wobble: 1)
        let widths = f.items.filter { $0.kind == .stroke && $0.color == .ink && $0.source > 0 && $0.source < 20 }.map { $0.width }
        #expect(Set(widths).count > 10)
        let lo = widths.min()!, hi = widths.max()!
        #expect(lo >= FigureStyle.creaseWidth * (1 - FigureStyle.lineVariation) - 1e-9)
        #expect(hi <= FigureStyle.silhouetteWidth * (1 + FigureStyle.lineVariation) + 1e-9)
    }

    @Test func darkSidesGetHatchingAndLitSidesDoNot() {
        let cam = FigureCamera(yaw: -32)
        let style = FigureStyle(wobble: 0)
        let solid = FigureShapes.box(id: 9, part: "b", layer: .shell, palette: .metal, min: Vec3(-5, -5, 0), max: Vec3(5, 5, 10))
        var items: [FigureItem] = []
        FigureRenderer.drawSolid(solid, alpha: 1, cam, style, &items)
        let hatches = items.filter { $0.kind == .hatch }
        #expect(!hatches.isEmpty)
        let light = style.lightDirection(cam)
        let litFaces = solid.normals.filter { cam.faces($0) && $0.dot(light) > 0.62 }.count
        let visible = solid.normals.filter { cam.faces($0) }.count
        #expect(litFaces < visible)
        #expect(Set(hatches.map { $0.source }) == [9])
    }

    @Test func hatchSegmentsStayInsideAndAreParallel() {
        let poly = [Vec2(0, 0), Vec2(20, 4), Vec2(18, 22), Vec2(-2, 16)]
        let angle = 52 * Double.pi / 180
        let segs = FigureHatch.segments(polygon: poly, angle: angle, spacing: 2)
        #expect(segs.count >= 20 && segs.count % 2 == 0)
        let d = Vec2(cos(angle), sin(angle))
        var i = 0
        while i < segs.count {
            let v = (segs[i + 1] - segs[i]).normalized
            #expect(abs(v.cross(d)) < 1e-9)
            for p in [segs[i], segs[i + 1]] {
                #expect(p.x >= -2.001 && p.x <= 20.001 && p.y >= -0.001 && p.y <= 22.001)
            }
            i += 2
        }
    }

    @Test func hatchLinesSitOnAGlobalGrid() {
        let a = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)]
        let b = [Vec2(10, 0), Vec2(20, 0), Vec2(20, 10), Vec2(10, 10)]
        let angle = 0.9, s = 1.7
        let nrm = Vec2(-sin(angle), cos(angle))
        for poly in [a, b] {
            let segs = FigureHatch.segments(polygon: poly, angle: angle, spacing: s)
            #expect(!segs.isEmpty)
            for p in segs { let t = p.dot(nrm) / s; #expect(abs(t - t.rounded()) < 1e-9) }
        }
    }

    @Test func jitterMovesTheEndsOnly() {
        let poly = [Vec2(0, 0), Vec2(20, 0), Vec2(20, 20), Vec2(0, 20)]
        let a = FigureHatch.segments(polygon: poly, angle: 0.8, spacing: 2)
        let b = FigureHatch.segments(polygon: poly, angle: 0.8, spacing: 2, key: 3, jitter: 0.5)
        #expect(a.count == b.count)
        let nrm = Vec2(-sin(0.8), cos(0.8))
        for (p, q) in zip(a, b) { #expect(abs(p.dot(nrm) - q.dot(nrm)) < 1e-9); #expect((p - q).length <= 0.5 + 1e-9) }
    }
}
