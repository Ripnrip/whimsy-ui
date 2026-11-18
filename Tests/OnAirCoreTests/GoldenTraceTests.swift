import Foundation
import Testing
@testable import OnAirCore

/// Eight-decimal trace shared with `webports/onair-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum OnAirGoldenTrace {
    static let dt = 1.0 / 60.0

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
            "dt \(fmt(dt))",
            "spring \(fmt(OnAirTuning.stiffness)) \(fmt(OnAirTuning.dampingRatio))",
            "threshold \(fmt(OnAirTuning.commitThreshold)) slop \(fmt(OnAirTuning.tapSlop))",
            "dim \(fmt(OnAirTuning.dimFloor)) breath \(fmt(OnAirTuning.breathPeriod)) \(fmt(OnAirTuning.breathDepth))",
            "reduce \(fmt(OnAirTuning.reduceDuration))",
            "pill \(fmt(OnAirTuning.pillX)) \(fmt(OnAirTuning.pillY)) \(fmt(OnAirTuning.pillWidth)) \(fmt(OnAirTuning.pillHeight))",
            "knob \(fmt(OnAirTuning.knobDiameter)) \(fmt(OnAirTuning.knobInset)) travel \(fmt(OnAirTuning.travel))",
            "copy \(OnAirTuning.onAirLabel) | \(OnAirClock.format(83))",
            "math \(fmt(OnAirMath.sin(0))) \(fmt(OnAirMath.sin(OnAirMath.halfPi))) \(fmt(OnAirMath.cos(0))) \(fmt(OnAirMath.cos(OnAirMath.pi)))",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = OnAirModel(reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [OnAirEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        let y = OnAirTuning.pillY + OnAirTuning.pillHeight / 2
        snap()
        for _ in 0..<4 {
            note(model.step(dt))
            snap()
        }
        note(model.setOn(true))
        snap()
        let coast = reduceMotion ? 24 : 130
        for _ in 0..<coast {
            note(model.step(dt))
            snap()
        }
        if !reduceMotion {
            let grabbed = model.beginDrag(sceneX: OnAirTuning.sceneX(forProgress: 0.82), sceneY: y)
            if !grabbed { note([.committed(false)]) }
            snap()
            for step in 1...6 {
                let progress = 0.82 - 0.12 * Double(step)
                model.updateDrag(sceneX: OnAirTuning.sceneX(forProgress: progress))
                note(model.step(dt))
                snap()
            }
            note(model.endDrag(translation: 48))
            snap()
            for _ in 0..<70 {
                note(model.step(dt))
                snap()
            }
        } else {
            note(model.setOn(false))
            snap()
            for _ in 0..<24 {
                note(model.step(dt))
                snap()
            }
        }
        return lines
    }

    private static func describe(_ event: OnAirEvent) -> String {
        switch event {
        case .committed(let on): return "committed \(on ? 1 : 0)"
        case .haptic: return "haptic"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: OnAirModel) -> String {
        let meter = model.meter.map(fmt).joined(separator: ",")
        return [
            tag, "\(index)", model.isOn ? "1" : "0", model.isDragging ? "1" : "0",
            fmt(model.throwProgress), fmt(model.spring.velocity),
            fmt(model.dimAmount), fmt(model.glow), fmt(model.backgroundMultiply),
            fmt(model.chromeOpacity), fmt(model.elapsed), model.timerText,
            "\"\(model.accessibilityValue)\"", meter,
        ].joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct OnAirGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = OnAirGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: OnAirGoldenTrace.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: OnAirGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: OnAirGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("copy ON AIR | 01:23"))
        #expect(got.contains("f e committed 1"))
        #expect(got.contains("f e haptic"))
        #expect(got.contains("r e committed 0"))
        #expect(got.contains("\"On air, 00:00\""))
    }
}
