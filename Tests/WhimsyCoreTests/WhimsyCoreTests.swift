import Testing
@testable import WhimsyCore

@Suite("WhimsyCore")
struct WhimsyCoreTests {
    @Test func vectorBasics() {
        let a = Vec2(3, 4)
        #expect(a.length == 5)
        #expect(a.normalized.distance(to: Vec2(0.6, 0.8)) < 1e-12)
        #expect(Vec2(1, 0).cross(Vec2(0, 1)) == 1)
        #expect(a.clamped(toRadius: 1).distance(to: Vec2(0.6, 0.8)) < 1e-12)
        #expect(Vec2(0.1, 0).clamped(toRadius: 1) == Vec2(0.1, 0))
        #expect(Vec2(1, 1).distance(toSegment: Vec2(0, 0), Vec2(2, 0)) == 1)
        #expect(Vec2.lerp(.zero, Vec2(2, 4), 0.5) == Vec2(1, 2))
    }

    @Test func splitMix64KnownValues() {
        // Reference outputs of SplitMix64 seeded with 0.
        var r = SeededRandom(seed: 0)
        #expect(r.next() == 0xE220_A839_7B1D_CDAF)
        #expect(r.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    @Test func uniformStaysInRangeAndIsReproducible() {
        var a = SeededRandom(seed: 99), b = SeededRandom(seed: 99)
        for _ in 0..<1000 {
            let x = a.uniform(-2...3)
            #expect(x >= -2 && x <= 3)
            #expect(x == b.uniform(-2...3))
            let y = a.double(in: 0...1)
            #expect(y == b.double(in: 0...1))
        }
    }
}
