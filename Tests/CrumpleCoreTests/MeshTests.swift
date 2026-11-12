import Testing
@testable import CrumpleCore

private let card = CrumpleRect(x: 0, y: 0, width: 200, height: 140)

@Test func flatGridAndCameraNormals() {
    let sample = CrumpleMesh.sample(card: card, shape: 0)
    #expect(sample.facets.count == 40)
    #expect(sample.vertices.count == 30)
    let center = card.center
    for vertex in sample.vertices {
        let dx = vertex.x - center.x
        let dy = vertex.y - center.y
        #expect(abs(vertex.z) < 1e-9)
        #expect(dx >= -100.01 && dx <= 100.01)
        #expect(dy >= -70.01 && dy <= 70.01)
    }
    for facet in sample.facets {
        #expect(abs(facet.normal.x) < 1e-6)
        #expect(abs(facet.normal.y) < 1e-6)
        #expect(facet.normal.z > 0.99)
    }
}

@Test func settledShapeSitsOnTheBall() {
    let sample = CrumpleMesh.sample(card: card, shape: 1)
    let ball = CrumpleMesh.ballRadius(card)
    let center = card.center
    for vertex in sample.vertices {
        let dx = vertex.x - center.x
        let dy = vertex.y - center.y
        #expect(abs((dx * dx + dy * dy).squareRoot() - ball) < 1e-6)
    }
}

@Test func halfwayHasNotCollapsed() {
    let flat = CrumpleMesh.sample(card: card, shape: 0)
    let mid = CrumpleMesh.sample(card: card, shape: 0.5)
    let ball = CrumpleMesh.ballRadius(card)
    let center = card.center
    var moved = false
    for (a, b) in zip(flat.vertices, mid.vertices) {
        let rest = ((a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y)).squareRoot()
        let now = ((b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y)).squareRoot()
        if rest > ball + 1 {
            #expect(now < rest - 1)
            #expect(now > ball + 1)
            moved = true
        }
    }
    #expect(moved)
}

@Test func sameSeedRedrawsAndAnotherSeedTilts() {
    let a = CrumpleMesh.sample(card: card, shape: 0.5)
    let b = CrumpleMesh.sample(card: card, shape: 0.5)
    #expect(a.vertices == b.vertices)
    #expect(a.facets.map(\.shade) == b.facets.map(\.shade))
    var other = CrumpleRules()
    other.seed = 35
    let flatA = CrumpleMesh.sample(card: card, shape: 0)
    let flatB = CrumpleMesh.sample(card: card, shape: 0, rules: other)
    #expect(flatA.vertices == flatB.vertices)
    let tilted = CrumpleMesh.sample(card: card, shape: 0.5, rules: other)
    #expect(tilted.vertices != a.vertices)
}

@Test func lightFacingIsBrighter() {
    let light = CrumpleShade.unitLight(CrumpleRules())
    let toward = CrumpleShade.lambert(normal: light, light: light)
    let away = CrumpleShade.lambert(normal: light * -1, light: light)
    #expect(toward > 0.99)
    #expect(away < 0.01)
    let sample = CrumpleMesh.sample(card: card, shape: 0.7)
    #expect(sample.facets.allSatisfy { $0.shade >= 0 && $0.shade <= 1 })
}

@Test func sharedEdgeCountIsStable() {
    let sample = CrumpleMesh.sample(card: card, shape: 0.4)
    #expect(sample.edges.count == 51)
    #expect(sample.edges.map(\.index) == Array(0..<51))
}

@Test func shapeClampsBelowZeroAndOvershootsAboveOne() {
    let flat = CrumpleMesh.sample(card: card, shape: 0)
    let below = CrumpleMesh.sample(card: card, shape: -0.4)
    #expect(below.vertices == flat.vertices)
    let ball = CrumpleMesh.ballRadius(card)
    let grown = CrumpleMesh.sample(card: card, shape: 1.08)
    let center = card.center
    for vertex in grown.vertices {
        let radius = ((vertex.x - center.x) * (vertex.x - center.x) + (vertex.y - center.y) * (vertex.y - center.y)).squareRoot()
        #expect(abs(radius - ball * 1.08) < 1e-6)
    }
}
