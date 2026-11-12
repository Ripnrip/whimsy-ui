import Foundation
import Testing
@testable import PinataCore

/// Eight-decimal trace shared with `webports/pinata-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum GoldenTrace {
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
        var lines: [String] = ["v1", "dt \(fmt(dt))"]
        for n in 1...8 {
            lines.append("imp \(n) \(fmt(PinataTuning.impulse(forHit: n)))")
        }
        lines.append("math \(fmt(PinataMath.sin(0))) \(fmt(PinataMath.sin(PinataMath.halfPi))) \(fmt(PinataMath.sin(PinataMath.pi))) \(fmt(PinataMath.cos(0))) \(fmt(PinataMath.exp(0))) \(fmt(PinataMath.exp(1))) \(fmt(PinataMath.sin(0.3)))")
        var rng = SeededRandom(seed: PinataTuning.defaultSeed)
        let mixed = rng.next()
        let unit = rng.uniform(-0.5...0.5)
        lines.append("seed \(mixed) \(fmt(unit))")
        lines.append("copy \(PinataTuning.keepTapping) | \(PinataTuning.comeBack)")
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = PinataModel(hitsToBreak: 8, seed: PinataTuning.defaultSeed, reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [PinataEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        snap()
        let rest = reduceMotion ? 4 : 12
        for _ in 0..<rest {
            note(model.step(dt))
            snap()
        }
        let between = reduceMotion ? 2 : 18
        for hit in 0..<8 {
            let side: PinataSide = hit % 2 == 0 ? .left : .right
            note(model.strike(side))
            snap()
            if hit < 7 {
                for _ in 0..<between {
                    note(model.step(dt))
                    snap()
                }
            }
        }
        let tail = reduceMotion ? 30 : 96
        for _ in 0..<tail {
            note(model.step(dt))
            snap()
        }
        return lines
    }

    private static func describe(_ event: PinataEvent) -> String {
        switch event {
        case .hit(let n, let side): return "hit \(n) \(side.rawValue)"
        case .burst: return "burst"
        case .settled: return "settled"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: PinataModel) -> String {
        var sumX = 0.0
        var sumY = 0.0
        for p in model.particles {
            sumX += p.position.x
            sumY += p.position.y
        }
        let h0 = model.halves.count > 0 ? model.halves[0] : nil
        let h1 = model.halves.count > 1 ? model.halves[1] : nil
        let pill = model.phase == .intact ? "keep" : "tomorrow"
        return [
            tag, "\(index)", model.phase.rawValue, "\(model.hits)",
            fmt(model.angle), fmt(model.omega), fmt(model.length), fmt(model.radialVelocity), fmt(model.glow),
            "\(model.particles.count)", "\(model.cracks.count)", fmt(sumX), fmt(sumY),
            fmt(h0?.position.x ?? 0), fmt(h0?.position.y ?? 0), fmt(h0?.angle ?? 0),
            fmt(h1?.position.x ?? 0), fmt(h1?.position.y ?? 0), fmt(h1?.angle ?? 0),
            fmt(model.token.scale), fmt(model.token.offset), pill,
        ].joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct GoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = GoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: GoldenTrace.fixtureURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try got.write(to: GoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: GoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("copy Keep tapping | Come back tomorrow"))
        #expect(got.contains("f e hit 8 right burst"))
        #expect(got.contains("f e settled"))
        #expect(got.contains("r e hit 8 right burst"))
        #expect(!got.contains("r e hit 1 left burst"))
    }
}
