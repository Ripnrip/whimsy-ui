import Foundation
import Testing
@testable import GlassPourCore

/// Eight-decimal trace shared with `webports/glasspour-core.mjs`.
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
        var lines = [
            "v1",
            "dt \(fmt(dt))",
            "longPress \(fmt(GlassPourTuning.longPress))",
            "stagger \(fmt(GlassPourTuning.stagger))",
            "spring \(fmt(GlassPourTuning.stiffness)) \(fmt(GlassPourTuning.dampingRatio))",
            "wobble \(fmt(GlassPourTuning.wobbleStiffness)) \(fmt(GlassPourTuning.wobbleDamping)) \(fmt(GlassPourTuning.wobbleKick)) \(fmt(GlassPourTuning.wobbleGate))",
            "neck \(fmt(GlassPourLayout.maxNeck)) \(fmt(GlassPourLayout.breakGap)) \(fmt(GlassPourLayout.waistThinning)) \(fmt(GlassPourTuning.neckMinimum))",
            "goo \(fmt(GlassPourLayout.gooBlur)) \(fmt(GlassPourLayout.gooThreshold))",
            "layout \(fmt(GlassPourLayout.width)) \(fmt(GlassPourLayout.dropRadius)) \(fmt(GlassPourLayout.pillWidth)) \(fmt(GlassPourLayout.pillHeight)) \(fmt(GlassPourLayout.rowGap))",
            "page \(fmt(GlassPourLayout.pageWidth)) \(fmt(GlassPourLayout.pageHeight)) \(fmt(GlassPourLayout.pageOrigin.x)) \(fmt(GlassPourLayout.pageOrigin.y))",
            "items \(GlassDropItem.defaults.map(\.title).joined(separator: " | "))",
            "copy \(GlassPourTuning.openedAnnouncement) | \(GlassPourTuning.closedAnnouncement)",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = GlassPourModel(reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [GlassPourEvent]) {
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
        frames(3)
        note(model.pressDrop())
        snap()
        frames(100)
        note(model.pressOutside())
        snap()
        frames(90)
        note(model.pressDrop())
        snap()
        frames(8)
        note(model.releaseDrop())
        snap()
        frames(3)
        note(model.activateDrop())
        snap()
        frames(90)
        note(model.selectRow(3))
        snap()
        frames(90)
        return lines
    }

    private static func describe(_ event: GlassPourEvent) -> String {
        switch event {
        case .opening: "opening"
        case .opened: "opened"
        case .closing: "closing"
        case .closed: "closed"
        case .selected(let index): "selected \(index)"
        case .pulsed: "pulsed"
        case .haptic: "haptic"
        }
    }

    private static func line(_ tag: String, _ index: Int, _ model: GlassPourModel) -> String {
        var fields = [
            tag, "\(index)", model.phase.rawValue,
            fmt(model.time), fmt(model.phaseTime), fmt(model.fade), fmt(model.dropScale),
        ]
        for row in model.rows {
            fields.append(contentsOf: [
                fmt(row.travel), fmt(row.center.y), fmt(row.scale), fmt(row.opacity), fmt(row.wobble), fmt(row.pinch),
            ])
        }
        let necks = model.necks.sorted { ($0.top, $0.x) < ($1.top, $1.x) }
        for slot in 0..<4 {
            if slot < necks.count {
                fields.append(fmt(necks[slot].width))
                fields.append(fmt(necks[slot].waist))
            } else {
                fields.append(fmt(0))
                fields.append(fmt(0))
            }
        }
        return fields.joined(separator: " ")
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
            try FileManager.default.createDirectory(
                at: GoldenTrace.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: GoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: GoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("items Share | Duplicate | Rename | Delete"))
        #expect(got.contains("copy Menu opened | Menu closed"))
        #expect(got.contains("f e opening"))
        #expect(got.contains("f e opened haptic"))
        #expect(got.contains("f e closing"))
        #expect(got.contains("f e closed"))
        #expect(got.contains("f e pulsed"))
        #expect(got.contains("f e selected 3 closing haptic"))
        #expect(got.contains("r e opened haptic"))
        #expect(!got.contains("r e pulsed opening"))
    }
}
