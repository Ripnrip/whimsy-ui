import Foundation
import Testing
@testable import VelocityGlyphCore

/// The scripted session the web port replays. Keep the sample counts in
/// `webports/velocityglyph-core.mjs` identical to `GoldenTrace.make()`.
enum GoldenTrace {
    static let dt = 1.0 / 60

    static func make() -> String {
        var lines: [String] = []
        lines.append("v1")
        lines.append("dt \(fmt(dt))")
        for role in [GlyphRole.currency, .sign, .digit(place: 0), .digit(place: 1), .digit(place: 2), .separator(group: 1)] {
            lines.append("unit \(role.token) \(fmt(VelocityGlyphMath.signedUnit(for: role)))")
        }
        for value in [40, 180, 600, 1000, -12] {
            lines.append("fmt \(value) \(PriceGlyphs.string(for: value))")
        }
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = VelocityGlyphModel(value: 180, reduceMotion: reduceMotion)
        var lines = [line(tag, 0, model)]
        var index = 1
        let start = model.interactionX
        _ = model.beginDrag(atX: start)
        let forward = reduceMotion ? 24 : 36
        for i in 1...forward {
            let x = start + (250 - start) * Double(i) / Double(forward)
            _ = model.updateDrag(atX: x)
            model.step(dt)
            lines.append(line(tag, index, model))
            index += 1
        }
        if !reduceMotion {
            let mid = model.interactionX
            for i in 1...18 {
                let x = mid + (80 - mid) * Double(i) / 18
                _ = model.updateDrag(atX: x)
                model.step(dt)
                lines.append(line(tag, index, model))
                index += 1
            }
        }
        model.endDrag()
        lines.append(line(tag, index, model))
        index += 1
        let tail = reduceMotion ? 12 : 90
        for _ in 0..<tail {
            model.step(dt)
            lines.append(line(tag, index, model))
            index += 1
        }
        return lines
    }

    private static func line(_ tag: String, _ index: Int, _ model: VelocityGlyphModel) -> String {
        var parts = ["\(tag) \(index) \(model.phase.rawValue) \(model.value) \(fmt(model.smoothedSpeed)) \(fmt(model.blurRadius))"]
        for pose in model.poses {
            parts.append("\(pose.id.token):\(pose.character):\(fmt(pose.offsetY)):\(fmt(pose.leanDegrees))")
        }
        return parts.joined(separator: " ")
    }

    static func fmt(_ x: Double) -> String { String(format: "%.8f", x) }

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
        #expect(got.contains("fmt 1000 $1,000"))
        #expect(got.contains("fmt -12 -$12"))
    }
}
