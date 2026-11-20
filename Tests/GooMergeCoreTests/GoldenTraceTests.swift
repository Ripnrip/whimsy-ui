import Foundation
import Testing
@testable import GooMergeCore

/// Eight-decimal trace shared with `webports/goomerge-core.mjs`.
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
        let omegas = GooMergeModel(drops: GooDrop.samples, seed: 11).bobOmegas.map(fmt).joined(separator: " ")
        var lines = [
            "v1",
            "dt \(fmt(dt))",
            "well \(fmt(GooMergeTuning.well.x)) \(fmt(GooMergeTuning.well.y))",
            "ring \(fmt(GooMergeTuning.ringRadius)) \(fmt(GooMergeTuning.wellDashRadius))",
            "radius \(fmt(GooMergeTuning.minRadius)) \(fmt(GooMergeTuning.maxRadius))",
            "spring \(fmt(GooMergeTuning.stiffness)) \(fmt(GooMergeTuning.dampingRatio))",
            "stretch \(fmt(GooMergeTuning.stretchReach)) \(fmt(GooMergeTuning.snapGap)) \(fmt(GooMergeTuning.stretchShift)) \(fmt(GooMergeTuning.attractSpeed))",
            "field \(fmt(GooMergeTuning.smoothK)) \(fmt(GooMergeTuning.fieldEpsilon)) \(fmt(GooMergeTuning.connectSDF))",
            "clock \(fmt(GooMergeTuning.arrival)) \(fmt(GooMergeTuning.morphDuration)) \(fmt(GooMergeTuning.reducedFade)) \(fmt(GooMergeTuning.bobAmplitude)) \(fmt(GooMergeTuning.bobOmega))",
            "goo \(fmt(GooMergeTuning.gooBlur)) \(fmt(GooMergeTuning.gooThreshold))",
            "card \(fmt(GooMergeTuning.cardWidth)) \(fmt(GooMergeTuning.cardHeight)) \(fmt(GooMergeTuning.cardRadius)) \(fmt(GooMergeTuning.foldSize))",
            "doc \(GooMergeTuning.documentName)",
            "copy \(GooMergeTuning.readyValue) | \(GooMergeTuning.mergingValue) | \(GooMergeTuning.mergedValue) | \(GooMergeTuning.combineAction)",
            "drops \(GooDrop.samples.map { "\($0.name) \(fmt($0.value))" }.joined(separator: " | "))",
            "omega \(omegas)",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var model = GooMergeModel(drops: GooDrop.samples, seed: 11, reduceMotion: reduceMotion)
        var lines: [String] = []
        var index = 0
        func snap() {
            lines.append(line(tag, index, model))
            index += 1
        }
        func note(_ events: [GooMergeEvent]) {
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
        frames(6)
        if !reduceMotion {
            _ = model.beginDrag(index: 0)
            lines.append("\(tag) e drag 0")
            snap()
            let home0 = model.bodies[0].home
            let home1 = model.bodies[1].home
            let reach = model.bodies[0].radius + model.bodies[1].radius
            let dir = (home0 - home1).normalized
            for gap in [72.0, 40.0, 24.0, 16.0, 4.0] {
                note(model.updateDrag(to: home1 + dir * (reach + gap)))
                snap()
                frames(4)
            }
            note(model.endDrag())
            snap()
            frames(8)
            model.reset()
            lines.append("\(tag) e reset")
            snap()
        }
        note(model.combine())
        snap()
        frames(reduceMotion ? 30 : 170)
        return lines
    }

    private static func line(_ tag: String, _ index: Int, _ model: GooMergeModel) -> String {
        var parts = [
            tag, "\(index)", model.phase.rawValue,
            fmt(model.time), fmt(model.mergeProgress), fmt(model.morphProgress),
            fmt(model.sdf(at: model.well)), fmt(model.metaball(at: model.well)),
            "\(model.connectedPairCount)",
        ]
        for body in model.bodies {
            parts.append(contentsOf: [
                fmt(body.center.x), fmt(body.center.y),
                fmt(body.renderCenter.x), fmt(body.renderCenter.y),
                fmt(body.stretch),
            ])
        }
        return parts.joined(separator: " ")
    }

    private static func describe(_ event: GooMergeEvent) -> String {
        switch event {
        case .combining: "combining"
        case .snapped(let a, let b): "snapped \(a) \(b)"
        case .haptic: "haptic"
        case .morphing: "morphing"
        case .merged(let name): "merged \(name)"
        }
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct GooMergeGoldenTraceTests {
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
        #expect(got.contains("doc Binder-01.pdf"))
        #expect(got.contains("copy Ready to combine | Merging | Merged into Binder-01.pdf | Combine"))
        #expect(got.contains("f e snapped 0 1 haptic"))
        #expect(got.contains("f e merged Binder-01.pdf"))
        #expect(got.contains("r e combining morphing haptic"))
        #expect(got.contains("r e merged Binder-01.pdf"))
    }
}
