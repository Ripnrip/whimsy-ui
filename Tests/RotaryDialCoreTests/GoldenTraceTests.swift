import Foundation
import Testing
@testable import RotaryDialCore

/// Eight-decimal trace shared with `webports/rotarydial-core.mjs`.
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
        var lines: [String] = [
            "v1",
            "dt \(fmt(dt))",
            "step \(fmt(RotaryDialTuning.holeStep))",
            "stop \(fmt(RotaryDialTuning.stopAngle))",
            "travel5 \(fmt(RotaryDialMath.travel(forDisplay: 5)))",
            "travel0 \(fmt(RotaryDialMath.travel(forDisplay: 0)))",
            "sin \(fmt(RotaryDialMath.sin(0))) \(fmt(RotaryDialMath.sin(0.3))) \(fmt(RotaryDialMath.sin(.pi)))",
            "shake \(fmt(RotaryDialMath.shakeOffset(at: 0.12, reduceMotion: false))) \(fmt(RotaryDialMath.shakeOffset(at: 0.12, reduceMotion: true)))",
            "copy \(RotaryDialTuning.restCaption) | \(RotaryDialTuning.wrongAnnouncement) | \(RotaryDialTuning.unlockedAnnouncement)",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = RotaryDialModel(code: "5216", reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [RotaryDialEvent]) {
            guard !events.isEmpty else { return }
            lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
        }
        func frames(_ count: Int) {
            for _ in 0..<count {
                note(model.step(dt))
                snap()
            }
        }
        snap()
        if reduceMotion {
            note(model.beginDrag(digit: 5))
            snap()
            let slice = RotaryDialMath.travel(forDisplay: 5) / 5
            for _ in 0..<5 {
                note(model.drag(byClockwise: slice))
                snap()
            }
            note(model.release())
            snap()
            for digit in [2, 1, 0] {
                note(model.enterDigit(digit))
                snap()
            }
            frames(40)
            for digit in [5, 2, 1, 6] {
                note(model.enterDigit(digit))
                snap()
            }
            frames(24)
            return lines
        }

        note(model.beginDrag(digit: 5))
        snap()
        let slice = RotaryDialMath.travel(forDisplay: 5) / 5
        for _ in 0..<8 {
            note(model.drag(byClockwise: slice))
            snap()
        }
        note(model.drag(byClockwise: -RotaryDialTuning.holeStep * 0.2))
        snap()
        note(model.release())
        snap()
        frames(36)
        for digit in [2, 1, 0] {
            note(model.enterDigit(digit))
            snap()
        }
        frames(100)
        for digit in [5, 2, 1, 6] {
            note(model.enterDigit(digit))
            snap()
        }
        frames(70)
        return lines
    }

    private static func describe(_ event: RotaryDialEvent) -> String {
        switch event {
        case .tick(let digit): return "tick \(digit)"
        case .committed(let digit): return "committed \(digit)"
        case .rejected: return "rejected"
        case .springBack: return "springBack"
        case .wrong: return "wrong"
        case .deleted: return "deleted"
        case .morphedKeypad: return "morphedKeypad"
        case .unlocked: return "unlocked"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: RotaryDialModel) -> String {
        let plate = model.visualPlate
        let entered = model.entered.isEmpty ? "-" : model.entered.map(String.init).joined()
        let drops = (0..<4).map { fmt(model.dropProgress(slot: $0)) }.joined(separator: ",")
        return [
            tag, "\(index)", model.phase.rawValue, model.face.rawValue, model.morphFrom.rawValue,
            entered,
            fmt(model.rotation), fmt(model.velocity), fmt(model.morph),
            fmt(model.shakeOffset), fmt(model.errorTint),
            fmt(plate.width), fmt(plate.height), fmt(plate.corner),
            drops,
            model.caption,
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
        #expect(got.contains("copy Drag a number to the stop | Incorrect, try again | Unlocked"))
        #expect(got.contains("f e committed 5 springBack"))
        #expect(got.contains("f e wrong"))
        #expect(got.contains("f e morphedKeypad"))
        #expect(got.contains("f e unlocked"))
        #expect(got.contains("r e committed 0 wrong"))
        #expect(got.contains("r e morphedKeypad"))
        #expect(got.contains("r e unlocked"))
    }
}
