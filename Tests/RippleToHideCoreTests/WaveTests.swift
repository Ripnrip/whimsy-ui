import Foundation
import Testing
@testable import RippleToHideCore

@Test func standardRulesMatchTheShaderLiterals() {
    let rules = RippleRules.standard
    #expect(rules.wavelength == 44)
    #expect(rules.speed == 240)
    #expect(rules.spatialDecay == 150)
    #expect(rules.timeDamping == 0.48)
    #expect(rules.frontSoftness == 20)
    #expect(rules.duration == 0.90)
    #expect(rules.amplitude == 14)
    #expect(rules.swapFraction == 0.5)
    #expect(rules.reduceMotionDuration == 0.28)
    #expect(abs(rules.reach - 216) < 1e-9)
}

@Test func rulesClampNonPositiveInputs() {
    let rules = RippleRules(wavelength: 0, speed: -5, spatialDecay: .nan, timeDamping: 0,
                            frontSoftness: -1, duration: 0, amplitude: .nan, swapFraction: 4,
                            reduceMotionDuration: -2)
    #expect(rules.wavelength == 1e-3)
    #expect(rules.speed == 1e-3)
    #expect(rules.spatialDecay == 150)
    #expect(rules.timeDamping == 1e-3)
    #expect(rules.frontSoftness == 1e-3)
    #expect(rules.duration == 1e-3)
    #expect(rules.amplitude == 14)
    #expect(rules.swapFraction == 1)
    #expect(rules.reduceMotionDuration == 1e-3)
}

@Test func displacementMatchesTheExpandedFormula() {
    let wave = RippleWave()
    let rules = wave.rules
    let samples: [(Double, Double)] = [
        (0, 0), (0, -0.2), (12, 0.2), (44, 0.35), (80, 0.5), (200, 0.9),
        (30, 0.01), (.infinity, 0.4), (10, .nan),
    ]
    for (d, t) in samples {
        let expected = expandedDisplacement(d, t, rules)
        #expect(abs(wave.displacement(distance: d, time: t) - expected) < 1e-12)
    }
}

@Test func quietBeforeTheStartAndPastTheFront() {
    let wave = RippleWave()
    #expect(wave.displacement(distance: 0, time: 0) == 0)
    #expect(wave.displacement(distance: 40, time: -1) == 0)
    #expect(wave.gate(distance: 10, time: 0) == 0)
    #expect(wave.timeDamp(time: 0) == 0)
    let t = 0.25
    let past = wave.rules.speed * t + wave.rules.frontSoftness + 5
    #expect(wave.displacement(distance: past, time: t) == 0)
    #expect(wave.gate(distance: past, time: t) == 0)
    #expect(wave.gate(distance: 0, time: t) == 1)
    let band = wave.rules.speed * t - wave.rules.frontSoftness / 2
    let mid = wave.gate(distance: band, time: t)
    #expect(mid > 0 && mid < 1)
}

@Test func dampingAndFalloffShrinkTheEnvelope() {
    let wave = RippleWave()
    #expect(wave.timeDamp(time: 0.2) > wave.timeDamp(time: 0.8))
    #expect(wave.falloff(distance: 10) > wave.falloff(distance: 80))
    #expect(abs(wave.falloff(distance: 0) - 1) < 1e-12)
    // A crest behind the front is smaller farther out, once the sine is aligned.
    let t = 0.4
    let near = abs(wave.displacement(distance: 0, time: t))
    let far = abs(wave.displacement(distance: wave.rules.wavelength, time: t))
    #expect(near > far)
}

@Test func sampleStaysOnTheRadiusAndMovesByTheDisplacement() {
    let wave = RippleWave()
    let tap = Vec2(20, 30)
    let position = Vec2(80, 60)
    let time = 0.37
    let amplitude = 14.0
    let sample = wave.samplePosition(position: position, tap: tap, time: time, amplitude: amplitude)
    let v = position - tap
    let d = v.length
    let expected = position - v * (wave.displacement(distance: d, time: time) * amplitude / d)
    #expect(abs(sample.x - expected.x) < 1e-9)
    #expect(abs(sample.y - expected.y) < 1e-9)
    #expect(abs(v.cross(sample - tap)) < 1e-6)
}

@Test func sampleAtTheTapAndForBadNumbersStaysPut() {
    let wave = RippleWave()
    let tap = Vec2(12, 18)
    #expect(wave.samplePosition(position: tap, tap: tap, time: 0.4, amplitude: 14) == tap)
    #expect(wave.samplePosition(position: Vec2(4, 5), tap: tap, time: .nan, amplitude: 14) == Vec2(4, 5))
    #expect(wave.samplePosition(position: Vec2(.nan, 0), tap: tap, time: 0.2, amplitude: 14) == .zero)
    let still = wave.samplePosition(position: Vec2(40, 10), tap: tap, time: 0, amplitude: 14)
    #expect(still == Vec2(40, 10))
}

@Test func amplitudeScalesTheOffset() {
    let wave = RippleWave()
    let position = Vec2(90, 20)
    let tap = Vec2(10, 20)
    let a = wave.samplePosition(position: position, tap: tap, time: 0.33, amplitude: 7)
    let b = wave.samplePosition(position: position, tap: tap, time: 0.33, amplitude: 14)
    // Both samples sit on the same horizontal line, and doubling amplitude doubles the shift.
    #expect(abs(a.y - 20) < 1e-9 && abs(b.y - 20) < 1e-9)
    #expect(abs((position.x - b.x) - 2 * (position.x - a.x)) < 1e-9)
}

@Test func rewindingTimeSendsTheFrontBack() {
    let wave = RippleWave()
    let early = wave.front(time: 0.2)
    let later = wave.front(time: 0.7)
    #expect(later > early)
    #expect(abs(wave.displacement(distance: 30, time: 0.7) - wave.displacement(distance: 30, time: 0.7)) < 1e-15)
    // A point the front has not reached yet is still when the clock is wound back past it.
    let d = wave.rules.speed * 0.5
    #expect(wave.displacement(distance: d + 30, time: 0.5) == 0)
    #expect(wave.displacement(distance: d - 10, time: 0.5) != 0)
}

@Test func passRadiusUsesTheFarthestCornerAndCapsAtTheReach() {
    let bounds = RippleBounds(x: 0, y: 0, width: 300, height: 188)
    let center = Vec2(150, 94)
    let reach = RippleRules.standard.reach
    let fromCenter = RippleWave.passRadius(tap: center, in: bounds, reach: reach)
    let cornerDistance = center.distance(to: Vec2(300, 188))
    #expect(abs(fromCenter - cornerDistance) < 1e-9)
    #expect(fromCenter < reach * 0.92)

    let fromCorner = RippleWave.passRadius(tap: .zero, in: bounds, reach: reach)
    #expect(abs(fromCorner - reach * 0.92) < 1e-9)

    let uncapped = RippleWave.passRadius(tap: .zero, in: bounds, reach: 0)
    #expect(abs(uncapped - Vec2.zero.distance(to: Vec2(300, 188))) < 1e-9)
}

@Test func shaderSourceRepeatsTheStandardConstantsAndFormula() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent("Sources/RippleToHide/Resources/RippleToHide.metal")
    let source = try String(contentsOf: url, encoding: .utf8)
    #expect(source.contains("[[ stitchable ]] float2 rippleToHide(float2 position, float2 tap, float time, float amplitude)"))
    #expect(source.contains("constant float kWavelength = 44.0;"))
    #expect(source.contains("constant float kSpeed = 240.0;"))
    #expect(source.contains("constant float kSpatialDecay = 150.0;"))
    #expect(source.contains("constant float kTimeDamping = 0.48;"))
    #expect(source.contains("constant float kFrontSoftness = 20.0;"))
    #expect(source.contains("return sin(k * d - w * t) * gate * exp(-t / kTimeDamping) * exp(-d / kSpatialDecay);"))
    #expect(source.contains("return position - (v / d) * (rippleDisplacement(d, time) * amplitude);"))
}

private func expandedDisplacement(_ d: Double, _ t: Double, _ rules: RippleRules) -> Double {
    guard t > 0, d.isFinite, t.isFinite else { return 0 }
    let d = max(d, 0)
    let k = 2 * Double.pi / rules.wavelength
    let front = rules.speed * t
    let gate = 1 - WhimsyMath.smoothstep(front - rules.frontSoftness, front, d)
    return sin(k * d - k * rules.speed * t) * gate * exp(-t / rules.timeDamping) * exp(-d / rules.spatialDecay)
}
