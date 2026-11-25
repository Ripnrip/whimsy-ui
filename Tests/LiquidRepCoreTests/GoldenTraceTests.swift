import Foundation
import Testing
@testable import LiquidRepDialCore

/// Eight-decimal trace shared with `webports/liquidrepdial-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum LiquidRepGolden {
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
        var lines = [
            "v1",
            "dt \(fmt(LiquidRepReel.dt))",
            "bounce \(fmt(LiquidRepTuning.bounce)) zeta \(fmt(LiquidRepTuning.dampingRatio))",
            "spring \(fmt(LiquidRepTuning.stiffness)) \(fmt(LiquidRepTuning.impulse)) \(fmt(LiquidRepTuning.sloshStiffness))",
            "slosh \(fmt(LiquidRepTuning.maxSlosh)) \(fmt(LiquidRepTuning.fullTilt))",
            "meniscus \(fmt(LiquidRepTuning.meniscusOmega)) \(fmt(LiquidRepTuning.meniscusTrim)) \(fmt(LiquidRepTuning.meniscusBulge))",
            "fade \(fmt(LiquidRepTuning.crossfadeDuration))",
            "dial \(fmt(LiquidRepTuning.dialCenter.x)) \(fmt(LiquidRepTuning.dialCenter.y)) \(fmt(LiquidRepTuning.dialDiameter)) \(fmt(LiquidRepTuning.ringRadius))",
            "sin \(fmt(LiquidRepMath.sin(0))) \(fmt(LiquidRepMath.sin(LiquidRepMath.halfPi))) \(fmt(LiquidRepMath.sin(LiquidRepMath.pi)))",
            "atan \(fmt(LiquidRepMath.atan(0))) \(fmt(LiquidRepMath.atan(1))) \(fmt(LiquidRepMath.atan2(1, 0)))",
            "reel \(LiquidRepReel.totalFrames) \(fmt(LiquidRepReel.duration))",
        ]
        lines += script()
        lines += reel()
        return lines.joined(separator: "\n") + "\n"
    }

    private static func script() -> [String] {
        var lines: [String] = []
        var model = LiquidRepModel(reps: 0, goal: 20, reduceMotion: false)
        func snap(_ tag: String, _ current: LiquidRepModel) { lines.append("\(tag) \(body(current))") }
        func note(_ tag: String, _ events: [LiquidRepEvent]) {
            if events.isEmpty {
                lines.append("\(tag) e")
            } else {
                lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
            }
        }
        snap("s", model)
        note("s", model.addRep())
        snap("s", model)
        for _ in 0..<12 {
            model.step(LiquidRepReel.dt)
            snap("s", model)
        }
        model.setTilt(LiquidTilt(roll: 0.15, pitch: 0.55))
        for _ in 0..<8 {
            model.step(LiquidRepReel.dt)
            snap("s", model)
        }
        note("s", model.setReps(20))
        snap("s", model)
        var reduced = LiquidRepModel(reps: 0, goal: 20, reduceMotion: true)
        note("r", reduced.setReps(12))
        snap("r", reduced)
        for _ in 0..<6 {
            reduced.step(LiquidRepReel.dt)
            snap("r", reduced)
        }
        reduced.setReduceMotion(true)
        snap("r", reduced)
        return lines
    }

    private static func reel() -> [String] {
        let frames = LiquidRepReel.stills.map(\.frame) + [0, 30, 31, 80, 420, LiquidRepReel.totalFrames - 1]
        var seen: [Int] = []
        var lines: [String] = []
        for frame in frames where !seen.contains(frame) {
            seen.append(frame)
            lines.append("f \(frame) \(body(LiquidRepReel.model(atFrame: frame)))")
        }
        return lines
    }

    private static func body(_ model: LiquidRepModel) -> String {
        let rim = model.rim
        return [
            "\(model.reps)",
            "\(model.goal)",
            fmt(model.targetFill),
            fmt(model.displayedFill),
            fmt(model.fillVelocity),
            fmt(model.sloshAngle),
            fmt(model.meniscus),
            fmt(model.meniscusEnvelope),
            fmt(model.glow),
            fmt(model.elapsed),
            fmt(rim.trim),
            fmt(rim.rotation),
            fmt(rim.leading.x),
            fmt(rim.leading.y),
            model.reduceMotion ? "1" : "0",
            model.atGoal ? "1" : "0",
        ].joined(separator: " ")
    }

    private static func describe(_ event: LiquidRepEvent) -> String {
        switch event {
        case .tick: "tick"
        case .goalReached: "goal"
        }
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct LiquidRepGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = LiquidRepGolden.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: LiquidRepGolden.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: LiquidRepGolden.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: LiquidRepGolden.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("s e tick"))
        #expect(got.contains(" goal"))
        #expect(got.contains("r e tick"))
        #expect(got.contains(" f ") == false)
    }
}
