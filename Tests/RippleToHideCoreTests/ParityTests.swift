import Foundation
import Testing
@testable import RippleToHideCore

private struct Golden: Decodable {
    struct Disp: Decodable { var d, t, v: Double }
    struct Sample: Decodable { var x, y, tapX, tapY, time, amplitude, sx, sy: Double }
    struct MaskRow: Decodable { var input, output: String }
    struct Pass: Decodable { var reach, fromCenter, fromCorner: Double }
    struct Step: Decodable {
        var events: [String]
        var phase: String
        var elapsed, shaderTime, shaderAmplitude, maskAmount: Double
        var showsMask: Bool
    }
    struct Rules: Decodable {
        var wavelength, speed, spatialDecay, timeDamping, frontSoftness: Double
        var duration, amplitude, swapFraction, reduceMotionDuration: Double
    }
    var rules: Rules
    var displacements: [Disp]
    var samples: [Sample]
    var masks: [MaskRow]
    var pass: Pass
    var full: [Step]
    var reduced: [Step]
}

@Test func swiftMatchesTheJavaScriptGoldenTrace() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent("webports/ripple-golden.json")
    let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    let rules = RippleRules.standard
    #expect(golden.rules.wavelength == rules.wavelength)
    #expect(golden.rules.speed == rules.speed)
    #expect(golden.rules.spatialDecay == rules.spatialDecay)
    #expect(golden.rules.timeDamping == rules.timeDamping)
    #expect(golden.rules.frontSoftness == rules.frontSoftness)
    #expect(golden.rules.duration == rules.duration)
    #expect(golden.rules.amplitude == rules.amplitude)
    #expect(golden.rules.swapFraction == rules.swapFraction)
    #expect(golden.rules.reduceMotionDuration == rules.reduceMotionDuration)

    let wave = RippleWave(rules: rules)
    for row in golden.displacements {
        let got = wave.displacement(distance: row.d, time: row.t)
        #expect(abs(got - row.v) < 1e-9, "d \(row.d) t \(row.t)")
    }
    for row in golden.samples {
        let got = wave.samplePosition(
            position: Vec2(row.x, row.y),
            tap: Vec2(row.tapX, row.tapY),
            time: row.time,
            amplitude: row.amplitude
        )
        #expect(abs(got.x - row.sx) < 1e-9)
        #expect(abs(got.y - row.sy) < 1e-9)
    }
    for row in golden.masks {
        #expect(BalanceMask.mask(row.input) == row.output)
    }
    let bounds = RippleBounds(x: 0, y: 0, width: 300, height: 188)
    #expect(abs(rules.reach - golden.pass.reach) < 1e-9)
    #expect(abs(RippleWave.passRadius(tap: Vec2(150, 94), in: bounds, reach: rules.reach) - golden.pass.fromCenter) < 1e-9)
    #expect(abs(RippleWave.passRadius(tap: .zero, in: bounds, reach: rules.reach) - golden.pass.fromCorner) < 1e-9)

    expectSameTrace(trace(reduceMotion: false), golden.full)
    expectSameTrace(trace(reduceMotion: true), golden.reduced)
}

private func expectSameTrace(_ got: [ComparableStep], _ want: [Golden.Step]) {
    #expect(got.count == want.count)
    for (index, step) in want.enumerated() where index < got.count {
        let row = got[index]
        #expect(row.events == step.events)
        #expect(row.phase == step.phase)
        #expect(row.showsMask == step.showsMask)
        #expect(abs(row.elapsed - step.elapsed) < 1e-9)
        #expect(abs(row.shaderTime - step.shaderTime) < 1e-9)
        #expect(abs(row.shaderAmplitude - step.shaderAmplitude) < 1e-9)
        #expect(abs(row.maskAmount - step.maskAmount) < 1e-9)
    }
}

private struct ComparableStep: Equatable {
    var events: [String]
    var phase: String
    var elapsed, shaderTime, shaderAmplitude, maskAmount: Double
    var showsMask: Bool
}

private func trace(reduceMotion: Bool) -> [ComparableStep] {
    var model = RippleModel(reduceMotion: reduceMotion)
    let tap = Vec2(140, 80)
    var log: [ComparableStep] = []
    func push(_ events: [RippleEvent]) {
        log.append(ComparableStep(
            events: events.map(eventName),
            phase: phaseName(model.phase),
            elapsed: model.elapsed,
            shaderTime: model.shaderTime,
            shaderAmplitude: model.shaderAmplitude,
            maskAmount: model.maskAmount,
            showsMask: model.showsMask
        ))
    }
    push(model.toggle(at: tap, passRadius: 72))
    for _ in 0..<20 { push(model.advance(by: 0.05)) }
    push(model.toggle(at: tap, passRadius: 72))
    for _ in 0..<20 { push(model.advance(by: 0.05)) }
    return log
}

private func eventName(_ event: RippleEvent) -> String {
    switch event {
    case .beganHiding: "beganHiding"
    case .beganRevealing: "beganRevealing"
    case .swappedToMask: "swappedToMask"
    case .swappedToDigits: "swappedToDigits"
    case .haptic: "haptic"
    case .settledHidden: "settledHidden"
    case .settledShown: "settledShown"
    }
}

private func phaseName(_ phase: RipplePhase) -> String {
    switch phase {
    case .shown: "shown"
    case .hiding: "hiding"
    case .hidden: "hidden"
    case .revealing: "revealing"
    }
}
