import Testing
@testable import VelocityGlyphCore

@Suite("Price glyphs") struct FormatTests {
    @Test func defaultPrices() {
        #expect(PriceGlyphs.string(for: 40) == "$40")
        #expect(PriceGlyphs.string(for: 180) == "$180")
        #expect(PriceGlyphs.string(for: 600) == "$600")
        #expect(PriceGlyphs.string(for: 0) == "$0")
    }

    @Test func thousandsSeparatorAndSign() {
        #expect(PriceGlyphs.string(for: 1000) == "$1,000")
        #expect(PriceGlyphs.string(for: 1_000_000) == "$1,000,000")
        #expect(PriceGlyphs.string(for: -12) == "-$12")
        #expect(PriceGlyphs.string(for: -1234) == "-$1,234")
    }

    @Test func intMinDoesNotTrap() {
        let text = PriceGlyphs.string(for: Int.min)
        #expect(text.hasPrefix("-$"))
        #expect(text.filter { $0.isNumber }.count == String(UInt64(Int.max) + 1).count)
    }

    @Test func rolesAreUniqueAndOrdered() {
        let glyphs = PriceGlyphs.glyphs(for: 1_234)
        #expect(glyphs.map(\.id.token) == ["c", "d3", "g1", "d2", "d1", "d0"])
        #expect(glyphs.map(\.character) == ["$", "1", ",", "2", "3", "4"])
        #expect(Set(glyphs.map(\.id)).count == glyphs.count)
    }

    @Test func placeIdentitySurvivesAnExtraDigit() {
        let low = Set(PriceGlyphs.glyphs(for: 99).map(\.id))
        let high = PriceGlyphs.glyphs(for: 100)
        #expect(low.contains(.currency))
        #expect(low.contains(.digit(place: 0)))
        #expect(low.contains(.digit(place: 1)))
        #expect(!low.contains(.digit(place: 2)))
        #expect(high.map(\.id).contains(.digit(place: 2)))
        #expect(low.isSubset(of: Set(high.map(\.id))))
    }

    @Test func joinedGlyphsMatchTheString() {
        for value in [40, 99, 100, 600, 999, 1000, -40, -1000] {
            #expect(PriceGlyphs.glyphs(for: value).map(\.character).joined() == PriceGlyphs.string(for: value))
        }
    }
}

@Suite("Price grid") struct SpanTests {
    private let span = PriceSpan(range: 40...600, step: 5)

    @Test func defaultGrid() {
        #expect(span.lower == 40 && span.last == 600 && span.step == 5)
        #expect(span.count == 113)
        #expect(span.contains(40) && span.contains(600) && span.contains(182) == false)
    }

    @Test func snapRoundsHalfAwayFromZeroOnTheStepIndex() {
        #expect(span.snap(40.0) == 40)
        #expect(span.snap(42.4) == 40)
        #expect(span.snap(42.5) == 45)
        #expect(span.snap(600.0) == 600)
        #expect(span.snap(10.0) == 40)
        #expect(span.snap(9_000.0) == 600)
        #expect(span.snap(Double.nan) == 40)
        #expect(span.snap(42) == 40)
    }

    @Test func fractionAndXRoundTripTheCentres() {
        #expect(span.fraction(for: 40) == 0)
        #expect(span.fraction(for: 600) == 1)
        #expect(abs(span.fraction(for: 180) - 140.0 / 560.0) < 1e-12)
        let width = VelocityGlyphTuning.trackWidth
        #expect(span.value(atX: 0, width: width) == 40)
        #expect(span.value(atX: width, width: width) == 600)
        #expect(span.value(atX: span.x(for: 180, width: width), width: width) == 180)
        #expect(span.value(atFraction: .nan) == 40)
        #expect(span.value(atX: 10, width: 0) == 40)
    }

    @Test func crossingsIncludeTheDestinationOnce() {
        #expect(span.steps(from: 40, to: 40) == [])
        #expect(span.steps(from: 40, to: 45) == [45])
        #expect(span.steps(from: 40, to: 60) == [45, 50, 55, 60])
        #expect(span.steps(from: 60, to: 40) == [55, 50, 45, 40])
        // Off-grid ends are snapped before the walk.
        #expect(span.steps(from: 41, to: 52) == [45, 50])
    }

    @Test func fullSweepHitsEveryStepOnce() {
        let up = span.steps(from: 40, to: 600)
        #expect(up.count == 112)
        #expect(up.first == 45 && up.last == 600)
        #expect(Set(up).count == up.count)
        #expect(up == up.sorted())
        let down = span.steps(from: 600, to: 40)
        #expect(down.count == 112 && down.first == 595 && down.last == 40)
    }

    @Test func degenerateStepAndDomainClamp() {
        let unit = PriceSpan(range: 40...50, step: 0)
        #expect(unit.step == 1 && unit.contains(40) && unit.contains(50))
        let huge = PriceSpan(range: -2_000_000_000...2_000_000_000, step: 5_000_000_000)
        #expect(huge.lower == -PriceSpan.domain && huge.upper == PriceSpan.domain)
        #expect(huge.step == PriceSpan.domain)
        let point = PriceSpan(range: 15...15, step: 5)
        #expect(point.count == 1 && point.snap(100) == 15 && point.fraction(for: 15) == 0)
    }

    @Test func fullDomainPreservesStepIndices() {
        let span = PriceSpan(range: -PriceSpan.domain...PriceSpan.domain, step: 1)
        #expect(span.snap(123) == 123)
        #expect(span.snap(-456) == -456)
        #expect(span.snap(0) == 0)
        #expect(span.value(atFraction: 0) == -PriceSpan.domain)
        #expect(span.value(atFraction: 1) == PriceSpan.domain)
        let model = VelocityGlyphModel(value: 123, range: -PriceSpan.domain...PriceSpan.domain, step: 1)
        #expect(model.value == 123)
        #expect(model.formattedPrice == "$123")
    }
}

@Suite("Scatter math") struct ScatterMathTests {
    @Test func signedUnitIsStableAndInsideTheOpenInterval() {
        let roles: [GlyphRole] = [.currency, .sign, .digit(place: 0), .digit(place: 1), .digit(place: 2), .separator(group: 1)]
        var sawPositive = false
        var sawNegative = false
        for role in roles {
            let a = VelocityGlyphMath.signedUnit(for: role)
            let b = VelocityGlyphMath.signedUnit(for: role)
            #expect(a == b)
            #expect(a > -1 && a < 1 && a != 0)
            sawPositive = sawPositive || a > 0
            sawNegative = sawNegative || a < 0
        }
        #expect(sawPositive && sawNegative)
        #expect(VelocityGlyphMath.signedUnit(for: .digit(place: 0)) != VelocityGlyphMath.signedUnit(for: .digit(place: 1)))
        for role in roles {
            let amplitude = VelocityGlyphMath.signedAmplitude(for: role)
            #expect(abs(amplitude) >= 0.45 && abs(amplitude) <= 1)
            #expect((amplitude < 0) == (VelocityGlyphMath.signedUnit(for: role) < 0))
        }
    }

    @Test func speedScaleClamps() {
        #expect(VelocityGlyphMath.speedScale(0) == 0)
        #expect(VelocityGlyphMath.speedScale(.nan) == 0)
        #expect(VelocityGlyphMath.speedScale(VelocityGlyphTuning.fullSpeed) == 1)
        #expect(VelocityGlyphMath.speedScale(-VelocityGlyphTuning.fullSpeed * 4) == 1)
        let half = VelocityGlyphMath.speedScale(VelocityGlyphTuning.fullSpeed / 2)
        #expect(abs(half - 0.5) < 1e-12)
    }

    @Test func scatterMatchesTheSeedAndTheClamp() {
        let role = GlyphRole.digit(place: 0)
        let amplitude = VelocityGlyphMath.signedAmplitude(for: role)
        let full = VelocityGlyphMath.scatter(for: role, speed: 10_000)
        #expect(full.offset == amplitude * VelocityGlyphTuning.maxOffset)
        #expect(full.lean == amplitude * VelocityGlyphTuning.maxLean)
        #expect(abs(full.offset) <= VelocityGlyphTuning.maxOffset)
        #expect(abs(full.lean) <= VelocityGlyphTuning.maxLean)
        let slow = VelocityGlyphMath.scatter(for: role, speed: VelocityGlyphTuning.fullSpeed / 2)
        #expect(abs(slow.offset - full.offset / 2) < 1e-9)
        #expect(VelocityGlyphMath.blur(forSpeed: 10_000) == VelocityGlyphTuning.maxBlur)
        #expect(VelocityGlyphMath.blur(forSpeed: 0) == 0)
    }

    @Test func smootherIsMonotoneAndFrameRateStable() {
        #expect(VelocityGlyphMath.smoothAlpha(dt: 0) == 0)
        #expect(VelocityGlyphMath.smoothAlpha(dt: -1) == 0)
        #expect(VelocityGlyphMath.smoothAlpha(dt: .nan) == 0)
        let small = VelocityGlyphMath.smoothAlpha(dt: 1.0 / 60)
        let larger = VelocityGlyphMath.smoothAlpha(dt: 1.0 / 30)
        #expect(small > 0 && small < larger && larger < 1)
        // A stalled frame does not blend harder than the frame cap.
        #expect(VelocityGlyphMath.smoothAlpha(dt: 5) == VelocityGlyphMath.smoothAlpha(dt: VelocityGlyphTuning.maxFrame))
        var speed = 0.0
        var previous = 0.0
        for _ in 0..<40 {
            speed = VelocityGlyphMath.smooth(previous: speed, raw: 120, dt: 1.0 / 60)
            #expect(speed >= previous && speed <= 120)
            previous = speed
        }
        #expect(speed > 100)
        #expect(VelocityGlyphMath.smooth(previous: 10, raw: .nan, dt: 0.1) == 10)
        #expect(abs(VelocityGlyphMath.polyExp(0) - 1) < 1e-9)
    }

    @Test func returnSpringOvershootsThenSettles() {
        var spring = WhimsySpring(value: 8, velocity: 0,
                                  stiffness: VelocityGlyphTuning.springStiffness,
                                  dampingRatio: VelocityGlyphTuning.springDamping)
        var lowest = spring.value
        for _ in 0..<180 {
            spring.step(toward: 0, dt: 1.0 / 60)
            lowest = min(lowest, spring.value)
        }
        #expect(lowest < -0.5)
        #expect(spring.isSettled(at: 0, tolerance: 0.02))
    }
}
