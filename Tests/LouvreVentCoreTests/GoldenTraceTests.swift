import Foundation
import Testing
@testable import LouvreVentCore

/// Eight-decimal trace shared with `webports/louvrevent-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum LouvreVentGoldenTrace {
    static let dt = 1.0 / 60.0
    static let span = LouvreVentTuning.defaultLower...LouvreVentTuning.defaultUpper

    static func fmt(_ x: Double) -> String {
        guard x.isFinite else { return "nan" }
        let negative = x < 0
        let rounded = (abs(x) * 100_000_000 + 0.5).rounded(.down)
        let whole = (rounded / 100_000_000).rounded(.down)
        var frac = (rounded - whole * 100_000_000).rounded(.toNearestOrAwayFromZero)
        var wholeOut = whole
        if frac >= 100_000_000 {
            frac -= 100_000_000
            wholeOut += 1
        }
        let digits = String(format: "%08d", Int(frac))
        return "\(negative ? "-" : "")\(Int(wholeOut)).\(digits)"
    }

    static func make() -> String {
        var lines: [String] = [
            "v1",
            "range \(LouvreVentTuning.defaultLower) \(LouvreVentTuning.defaultUpper) blades \(LouvreVentTuning.bladeCount)",
            "angle \(fmt(LouvreVentTuning.minAngle)) \(fmt(LouvreVentTuning.maxAngle))",
            "opening \(fmt(LouvreVentTuning.openingX)) \(fmt(LouvreVentTuning.openingY)) \(fmt(LouvreVentTuning.openingWidth)) \(fmt(LouvreVentTuning.openingHeight))",
            "face \(fmt(LouvreVentTuning.bladeFaceRatio))",
            "spring \(fmt(LouvreVentTuning.stiffness)) \(fmt(LouvreVentTuning.dampingRatio)) \(fmt(LouvreVentTuning.settleTolerance))",
            "sweep \(fmt(LouvreVentTuning.sweepRise)) \(fmt(LouvreVentTuning.sweepFall)) \(fmt(LouvreVentTuning.sweepOmega)) \(fmt(LouvreVentTuning.specularSweepAmplitude))",
            "spec \(fmt(LouvreVentTuning.specularStart)) \(fmt(LouvreVentTuning.specularTravel)) \(fmt(LouvreVentTuning.specularBladePhase))",
            "glow \(fmt(LouvreVentTuning.coolRed)) \(fmt(LouvreVentTuning.coolGreen)) \(fmt(LouvreVentTuning.coolBlue)) \(fmt(LouvreVentTuning.coolIntensity)) \(fmt(LouvreVentTuning.hotRed)) \(fmt(LouvreVentTuning.hotGreen)) \(fmt(LouvreVentTuning.hotBlue)) \(fmt(LouvreVentTuning.hotIntensity))",
            "math \(fmt(LouvreVentMath.sin(0))) \(fmt(LouvreVentMath.sin(LouvreVentMath.halfPi))) \(fmt(LouvreVentMath.cos(0))) \(fmt(LouvreVentMath.cos(LouvreVentMath.pi))) \(fmt(LouvreVentMath.faceScale(angleDegrees: 70)))",
        ]
        for temperature in LouvreVentTuning.defaultLower...LouvreVentTuning.defaultUpper {
            let unit = LouvreVentMath.unit(temperature: temperature, range: span)
            let glow = LouvreVentMath.glow(unit: unit)
            let specs = (0..<LouvreVentTuning.bladeCount).map {
                fmt(LouvreVentMath.specular(blade: $0, unit: unit, sweep: 0, reduceMotion: false))
            }.joined(separator: ",")
            lines.append([
                "map", "\(temperature)",
                fmt(LouvreVentMath.angle(unit: unit)),
                fmt(glow.red), fmt(glow.green), fmt(glow.blue), fmt(glow.intensity),
                fmt(LouvreVentMath.faceScale(angleDegrees: LouvreVentMath.angle(unit: unit))),
                specs,
            ].joined(separator: " "))
        }
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = LouvreVentModel(temperature: 60, reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [LouvreVentEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        snap()
        note(model.setTemperature(68))
        snap()
        let coast = reduceMotion ? 4 : 20
        for _ in 0..<coast {
            model.step(dt)
            snap()
        }
        let startY = LouvreVentMath.sceneY(forTemperature: 68, range: span)
        let endY = LouvreVentMath.sceneY(forTemperature: 80, range: span)
        note(model.beginDrag(sceneY: startY))
        snap()
        for step in 1...8 {
            let y = startY + (endY - startY) * Double(step) / 8
            note(model.updateDrag(sceneY: y))
            model.step(dt)
            snap()
        }
        model.endDrag()
        snap()
        let settle = reduceMotion ? 4 : 36
        for _ in 0..<settle {
            model.step(dt)
            snap()
        }
        return lines
    }

    private static func describe(_ event: LouvreVentEvent) -> String {
        switch event {
        case .tick(let degree): return "tick:\(degree)"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: LouvreVentModel) -> String {
        let glow = model.glow
        let specs = (0..<LouvreVentTuning.bladeCount).map { fmt(model.specularOffset(blade: $0)) }.joined(separator: ",")
        return [
            tag, "\(index)", "\(model.temperature)", model.isDragging ? "1" : "0",
            fmt(model.targetUnit), fmt(model.displayedUnit),
            fmt(model.targetAngle), fmt(model.displayAngle),
            fmt(glow.red), fmt(glow.green), fmt(glow.blue), fmt(glow.intensity),
            fmt(model.sweepEnvelope), fmt(model.sweepPhase), fmt(model.sweepSignal),
            fmt(model.specularIntensity()),
            specs,
            fmt(model.slots[0].projectedHeight),
            "\"\(model.accessibilityValue)\"",
        ].joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct LouvreVentGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = LouvreVentGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: LouvreVentGoldenTrace.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: LouvreVentGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: LouvreVentGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("map 60 0.00000000"))
        #expect(got.contains("map 85 70.00000000"))
        #expect(got.contains("f e tick:61"))
        #expect(got.contains("f e tick:80"))
        #expect(got.contains("r e tick:61"))
        #expect(got.contains("\"60 degrees\""))
        #expect(got.contains("\"80 degrees\""))
    }
}
