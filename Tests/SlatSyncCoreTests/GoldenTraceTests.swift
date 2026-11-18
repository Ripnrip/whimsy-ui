import Foundation
import Testing
@testable import SlatSyncCore

/// Eight-decimal trace shared with `webports/slatsync-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum SlatGoldenTrace {
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
        var lines = ["v1", "slats \(SlatSyncTuning.slatCount)"]
        for index in 0..<SlatSyncTuning.slatCount {
            let optics = SlatSyncMath.optics(index: index)
            lines.append("o \(index) \(fmt(optics.blur)) \(fmt(optics.offsetX)) \(fmt(optics.tilt))")
        }
        for index in 0..<SlatSyncTuning.slatCount {
            let color = SlatSyncMath.color(index: index)
            lines.append("c \(index) \(fmt(color.red)) \(fmt(color.green)) \(fmt(color.blue))")
        }
        let samples = [0.0, 0.25, 0.42, 0.5, 0.75, 0.994, 0.995, 1.0, -0.2, 1.4]
        for progress in samples {
            for index in 0..<SlatSyncTuning.slatCount {
                lines.append("s \(fmt(progress)) \(index) \(fmt(SlatSyncMath.spread(index: index, progress: progress)))")
            }
            let pct = SlatSyncMath.percent(for: progress)
            let label = SlatSyncMath.label(for: pct)
            lines.append("pct \(fmt(progress)) \(pct) \(label.rawValue) \(SlatSyncMath.voiceOver(percent: pct))")
        }
        lines.append("pct nan \(SlatSyncMath.percent(for: .nan)) \(SlatSyncMath.voiceOver(percent: 0))")

        var monitor = SlatSyncMonitor()
        for next in [0.2, 0.42, 0.994, 0.995, 1.0, 1.0, 0.4, 1.0] {
            let fired = monitor.setProgress(next)
            lines.append("h \(fmt(next)) \(fired ? 1 : 0) \(monitor.hapticCount)")
        }

        let attitudes: [(Double, Double, Bool)] = [
            (0.2, 0, false),
            (0, 0.3, false),
            (2, -2, false),
            (0.2, 0.3, true),
            (.nan, 0.2, false),
        ]
        for (roll, pitch, reduced) in attitudes {
            for index in 0..<SlatSyncTuning.slatCount {
                let wobble = SlatSyncMath.wobble(index: index, roll: roll, pitch: pitch, reduceMotion: reduced)
                lines.append("w \(index) \(fmt(roll)) \(fmt(pitch)) \(reduced ? 1 : 0) \(fmt(wobble.offsetX)) \(fmt(wobble.tilt))")
            }
        }
        for index in 0..<SlatSyncTuning.slatCount {
            let frame = SlatSyncMath.frame(index: index)
            lines.append("l \(index) \(fmt(frame.x)) \(fmt(frame.y)) \(fmt(frame.width)) \(fmt(frame.height))")
        }
        let scenes: [(Double, Double, Double, Bool)] = [
            (0, 0, 0, false),
            (0.42, 0.15, -0.1, false),
            (1, 0.2, 0.1, false),
            (0.5, 0.4, 0.2, true),
        ]
        for (progress, roll, pitch, reduced) in scenes {
            let scene = SlatSyncScene.make(progress: progress, roll: roll, pitch: pitch, reduceMotion: reduced)
            lines.append("scene \(fmt(progress)) \(fmt(roll)) \(fmt(pitch)) \(reduced ? 1 : 0) \(scene.percent) \(scene.label.rawValue)")
            for band in scene.bands {
                lines.append(["b \(band.index)", fmt(band.spread), fmt(band.blur), fmt(band.offsetX),
                              fmt(band.tilt), fmt(band.edge), fmt(band.opacity),
                              fmt(band.red), fmt(band.green), fmt(band.blue)].joined(separator: " "))
            }
        }
        for time in [0.0, 0.35, 0.5, 2.1, 3.85, 4.0, Double.nan] {
            lines.append("demo \(fmt(time)) \(fmt(SlatSyncMath.demoProgress(at: time)))")
        }
        lines.append("copy \(SlatSyncTuning.title) | \(SlatSyncTuning.subtitle) | \(SlatSyncTuning.syncing) | \(SlatSyncTuning.synced) | \(SlatSyncTuning.detail)")
        return lines.joined(separator: "\n") + "\n"
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct SlatGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = SlatGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: SlatGoldenTrace.fixtureURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try got.write(to: SlatGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: SlatGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("copy Halo Vault | Studio library | Syncing… | All synced | 1,284 files · 3 devices"))
        #expect(got.contains("pct 0.42000000 42 Syncing… Syncing, 42 percent"))
        #expect(got.contains("pct 1.00000000 100 All synced All synced"))
        #expect(got.contains("h 0.99500000 1 1"))
        #expect(got.contains("h 1.00000000 0 1"))
        #expect(got.contains("h 1.00000000 1 2"))
    }
}
