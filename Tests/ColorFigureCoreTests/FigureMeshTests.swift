import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct FigureMeshTests {
    let box = FigureShapes.box(id: 1, part: "b", layer: .shell, palette: .metal, min: Vec3(-1, -2, 0), max: Vec3(3, 2, 4))

    @Test func boxHasTheRightTopology() {
        #expect(box.vertices.count == 8)
        #expect(box.faces.count == 6)
        #expect(box.edges.count == 12)
        #expect(box.edges.allSatisfy { $0.faceA >= 0 && $0.faceB >= 0 && $0.hard })
    }

    @Test func normalsPointOutward() {
        for (i, f) in box.faces.enumerated() {
            let c = f.map { box.vertices[$0] }.reduce(Vec3.zero, +) * (1 / Double(f.count))
            #expect((c - box.centre).dot(box.normals[i]) > 0)
            #expect(abs(box.normals[i].length - 1) < 1e-9)
        }
        let cyl = FigureShapes.cylinder(id: 2, part: "c", layer: .shell, palette: .metal, axis: .x, centre: (1, 2), from: 0, to: 3, radius: 2)
        for (i, f) in cyl.faces.enumerated() {
            let c = f.map { cyl.vertices[$0] }.reduce(Vec3.zero, +) * (1 / Double(f.count))
            #expect((c - cyl.centre).dot(cyl.normals[i]) > 0)
        }
    }

    @Test func boundsMatchTheCorners() {
        #expect(box.bounds.min == Vec3(-1, -2, 0) && box.bounds.max == Vec3(3, 2, 4))
        let t = box.translated(Vec3(10, 0, 5))
        #expect(t.bounds.min == Vec3(9, -2, 5) && t.bounds.max == Vec3(13, 2, 9))
    }

    @Test func rotatingAQuarterTurnSwapsExtents() {
        let r = box.rotated(.z, about: Vec3(0, 0, 0), by: Double.pi / 2)
        #expect(abs(r.bounds.max.x - 2) < 1e-9 && abs(r.bounds.min.x + 2) < 1e-9)
        #expect(abs(r.bounds.max.y - 3) < 1e-9 && abs(r.bounds.min.y + 1) < 1e-9)
        for (i, n) in r.normals.enumerated() {
            let c = r.faces[i].map { r.vertices[$0] }.reduce(Vec3.zero, +) * 0.25
            #expect((c - r.centre).dot(n) > 0)
        }
    }

    @Test func cylinderRimsAreHardAndTheSidesSoft() {
        let cyl = FigureShapes.cylinder(id: 2, part: "c", layer: .shell, palette: .metal, axis: .z, centre: (0, 0), from: 0, to: 2, radius: 1, segments: 14)
        let hard = cyl.edges.filter { $0.hard }.count
        #expect(hard == 28)               // both rims, 14 segments each
        #expect(cyl.edges.count == 14 * 3)
    }

    @Test func rodSpansItsEndpoints() {
        let r = FigureShapes.rod(id: 3, part: "r", layer: .interior, palette: .glass, from: Vec3(0, 0, 0), to: Vec3(0, 0, 10), halfWidth: 2)
                #expect(abs(r.bounds.min.z) < 1e-6 && abs(r.bounds.max.z - 10) < 1e-6)
        #expect(abs(r.bounds.max.x - 2) < 1e-6 && abs(r.bounds.min.y + 2) < 1e-6)
    }

    @Test func tonesComeFromThePalette() {
        let p = FigurePalette(base: 0xE4573D)
        #expect(FigureTone.color(dot: 1, palette: p) == p.light)
        #expect(FigureTone.color(dot: -1, palette: p) == p.dark)
        let m = FigureTone.color(dot: 0.37, palette: p)
        #expect(m == p.mid)
    }

    @Test func tonesBlendSmoothlyAcrossThresholds() {
        let p = FigurePalette(base: 0x4F7FD0)
        func lum(_ c: FigureColor) -> Double { 0.3 * c.r + 0.59 * c.g + 0.11 * c.b }
        var last = lum(FigureTone.color(dot: -1, palette: p))
        var maxStep = 0.0
        for i in 0...400 {
            let l = lum(FigureTone.color(dot: -1 + 2 * Double(i) / 400, palette: p))
            #expect(l >= last - 1e-9)       // never darker as the face turns toward the light
            maxStep = max(maxStep, l - last)
            last = l
        }
        #expect(maxStep < 0.03)
    }

    @Test func hatchDensityFollowsTheShade() {
        #expect(FigureTone.hatchDensity(dot: 0.9) == 0)
        #expect(FigureTone.hatchDensity(dot: -0.9) == 1)
        #expect(FigureTone.hatchDensity(dot: 0.2) > FigureTone.hatchDensity(dot: 0.4))
    }

    @Test func swatchesAreTheFiveColours() {
        #expect(GumballSwatch.allCases.map { $0.rawValue } == ["tomato", "mustard", "mint", "cobalt", "blush"])
        #expect(Set(GumballSwatch.allCases.map { $0.base }).count == 5)
        #expect(GumballSwatch.cobalt.title == "Cobalt")
    }
}
