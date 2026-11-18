import Foundation
import Testing
@testable import GlassMorphCore

/// Eight-decimal trace shared with `webports/glassmorph-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum GlassGoldenTrace {
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
        var lines = [
            "v1",
            "dt \(fmt(dt))",
            "k \(fmt(GlassMorphTuning.morphStiffness)) \(fmt(GlassMorphTuning.morphDamping))",
            "hold \(fmt(GlassMorphTuning.holdDuration)) \(fmt(GlassMorphTuning.unfoldDuration)) \(fmt(GlassMorphTuning.fadeDuration))",
            "tilt \(fmt(GlassMorphTuning.cardTilt))",
            "card \(fmt(GlassMorphTuning.cardWidth)) \(fmt(GlassMorphTuning.cardHeight)) \(fmt(GlassMorphTuning.stageCenter.x)) \(fmt(GlassMorphTuning.stageCenter.y))",
            "pill \(fmt(GlassMorphTuning.pillWidth)) \(fmt(GlassMorphTuning.pillHeight))",
            "copy \(GlassMorphTuning.defaultAmount) | \(GlassMorphTuning.defaultLabel) | \(GlassMorphTuning.payTitle) | \(GlassMorphTuning.announcement)",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = GlassMorphModel(reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        var ignored = false
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [GlassMorphEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        snap()
        for _ in 0..<6 {
            note(model.step(dt))
            snap()
        }
        note(model.pay())
        snap()
        for _ in 0..<360 {
            if !ignored, model.phase == .pill, model.phaseAge > 0.25 {
                note(model.pay())
                ignored = true
            }
            let events = model.step(dt)
            note(events)
            snap()
            if model.phase == .card, model.clock > 0.2 { break }
        }
        for _ in 0..<4 {
            note(model.step(dt))
            snap()
        }
        return lines
    }

    private static func describe(_ event: GlassMorphEvent) -> String {
        switch event {
        case .paid: "paid"
        case .settled: "settled"
        case .unfolding: "unfolding"
        case .returned: "returned"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: GlassMorphModel) -> String {
        let frame = model.frame
        let amber = model.amber
        let red = model.red
        return [
            tag, "\(index)", model.phase.rawValue,
            fmt(model.progress), fmt(model.progressVelocity), fmt(model.flipAngle),
            fmt(frame.width), fmt(frame.height), fmt(frame.tilt),
            fmt(amber.center.x), fmt(amber.center.y), fmt(amber.radius), fmt(amber.blur),
            fmt(red.center.x), fmt(red.center.y), fmt(red.radius), fmt(red.blur),
            fmt(model.cardContentOpacity), fmt(model.dotOpacity), fmt(model.glowOpacity), fmt(model.edgeGlow),
        ].joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct GlassGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = GlassGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: GlassGoldenTrace.fixtureURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try got.write(to: GlassGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: GlassGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("copy $48.00 | Solune | Pay | Payment complete"))
        #expect(got.contains("f e settled"))
        #expect(got.contains("f e unfolding"))
        #expect(got.contains("f e returned"))
        #expect(got.contains("r e settled"))
        #expect(got.contains("r e returned"))
        #expect(!got.contains("f e settled settled"))
    }
}
