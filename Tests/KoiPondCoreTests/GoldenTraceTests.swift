import Foundation
import Testing
@testable import KoiPondCore

/// Eight-decimal trace shared with `webports/koipond-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum KoiPondGoldenTrace {
    static let dt = KoiPondTuning.fixedStep

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
            "press \(fmt(KoiPondTuning.longPress)) stagger \(fmt(KoiPondTuning.stagger))",
            "segment \(fmt(KoiPondTuning.segmentLength)) spine \(KoiPondTuning.spineCount)",
            "tail \(fmt(KoiPondTuning.tailOmega)) \(fmt(KoiPondTuning.tailAmplitude)) \(fmt(KoiPondTuning.tailLag))",
            "seek \(fmt(KoiPondTuning.seekSpeed)) scatter \(fmt(KoiPondTuning.scatterSpeed)) reduce \(fmt(KoiPondTuning.reduceScale))",
            "gap \(fmt(KoiPondTuning.nibbleGap)) bob \(fmt(KoiPondTuning.bobOmega)) \(fmt(KoiPondTuning.nibbleThreshold))",
            "center \(fmt(KoiPondTuning.feedPoint.x)) \(fmt(KoiPondTuning.feedPoint.y))",
            "math \(fmt(KoiPondMath.sin(0))) \(fmt(KoiPondMath.sin(KoiPondMath.halfPi))) \(fmt(KoiPondMath.atan(1))) \(fmt(KoiPondMath.atan2(-1, -1)))",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = KoiPondModel(seed: KoiPondTuning.defaultSeed, reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [KoiPondEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        let finger = KoiPondTuning.feedPoint
        snap()
        for _ in 0..<12 {
            note(model.step(dt))
            snap()
        }
        note(model.beginTouch(at: finger))
        snap()
        for _ in 0..<8 {
            note(model.step(dt))
            snap()
        }
        let moved = Vec2(finger.x + 24, finger.y - 16)
        model.updateTouch(at: moved)
        snap()
        let gatherFrames = reduceMotion ? 80 : 150
        for _ in 0..<gatherFrames {
            note(model.step(dt))
            snap()
        }
        note(model.endTouch())
        snap()
        let after = reduceMotion ? 40 : 80
        for _ in 0..<after {
            note(model.step(dt))
            snap()
        }
        return lines
    }

    private static func describe(_ event: KoiPondEvent) -> String {
        switch event {
        case .nibble(let index): return "nibble \(index)"
        case .released: return "released"
        case .returned: return "returned"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: KoiPondModel) -> String {
        let arrivals = model.arrivalOrder.map(String.init).joined(separator: ",")
        var parts = [
            tag, "\(index)", model.phase.rawValue, fmt(model.time), fmt(model.swimTime),
            model.holding ? "1" : "0", fmt(model.finger.x), fmt(model.finger.y),
            "\(model.nibbleCount)", "\(model.ripples.count)",
            arrivals.isEmpty ? "-" : arrivals,
        ]
        for fish in model.fish {
            let posed = fish.posedSpine(at: model.swimTime)
            let tail = posed[posed.count - 1]
            parts.append(contentsOf: [
                fmt(fish.head.x), fmt(fish.head.y), fmt(fish.heading), fish.mode.rawValue,
                fmt(tail.x), fmt(tail.y),
            ])
        }
        if let ripple = model.ripples.first {
            parts.append(contentsOf: [ripple.kind.rawValue, fmt(ripple.radius), fmt(ripple.opacity)])
        } else {
            parts.append("none")
        }
        return parts.joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct KoiPondGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = KoiPondGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: KoiPondGoldenTrace.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: KoiPondGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: KoiPondGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("f e nibble"))
        #expect(got.contains("f e released"))
        #expect(got.contains("r e released"))
    }
}
