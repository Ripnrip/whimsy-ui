import Foundation
import Testing
@testable import CrumpleCore

private struct Golden: Decodable {
    struct Sample: Decodable {
        var shape: Double
        var vertices: [[Double]]
        var shades: [Double]
        var folds: [Double]
    }
    struct Gesture: Decodable {
        var creases: [Int]
        var committed: Bool
        var arrived: Bool
        var lidBump: Bool
    }
    var card: [Double]
    var bin: [Double]
    var light: [Double]
    var edgeCount: Int
    var triangleCount: Int
    var samples: [Sample]
    var gesture: Gesture
}

@Test func swiftMatchesGoldenTrace() throws {
    let url = URL(fileURLWithPath: "webports/crumple-golden.json")
    let data = try Data(contentsOf: url)
    let golden = try JSONDecoder().decode(Golden.self, from: data)
    let card = CrumpleRect(x: golden.card[0], y: golden.card[1], width: golden.card[2], height: golden.card[3])
    let bin = CrumpleRect(x: golden.bin[0], y: golden.bin[1], width: golden.bin[2], height: golden.bin[3])
    let light = CrumpleShade.unitLight(CrumpleRules())
    #expect(abs(light.x - golden.light[0]) < 1e-5)
    #expect(abs(light.y - golden.light[1]) < 1e-5)
    #expect(abs(light.z - golden.light[2]) < 1e-5)
    for sample in golden.samples {
        let got = CrumpleMesh.sample(card: card, shape: sample.shape)
        #expect(got.facets.count == golden.triangleCount)
        #expect(got.edges.count == golden.edgeCount)
        for (index, vertex) in got.vertices.enumerated() {
            #expect(abs(vertex.x - sample.vertices[index][0]) < 1e-5)
            #expect(abs(vertex.y - sample.vertices[index][1]) < 1e-5)
            #expect(abs(vertex.z - sample.vertices[index][2]) < 1e-5)
        }
        for (index, facet) in got.facets.enumerated() {
            #expect(abs(facet.shade - sample.shades[index]) < 1e-5)
        }
        let folds = CrumpleMesh.foldAngles(got)
        for (index, angle) in folds.enumerated() {
            #expect(abs(angle - sample.folds[index]) < 1e-5)
        }
    }
    var model = CrumpleModel(card: card, bin: bin)
    #expect(model.begin(at: card.center) == true)
    let creases = model.drag(to: card.center + (bin.center - card.center)).compactMap { event -> Int? in
        if case .crease(let id) = event { return id }
        return nil
    }
    #expect(creases == golden.gesture.creases)
    let end = model.end()
    #expect((end == [.committed]) == golden.gesture.committed)
    let flight = model.run(2)
    #expect(flight.contains(.arrived) == golden.gesture.arrived)
    #expect(flight.contains(.lidBump) == golden.gesture.lidBump)
}
