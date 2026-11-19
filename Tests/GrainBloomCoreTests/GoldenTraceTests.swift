import Foundation
import Testing
@testable import GrainBloomCore

enum GrainBloomGoldenTrace {
    static let dt = 0.1

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
            "wake \(fmt(GrainBloomTuning.wakeDuration)) resolve \(fmt(GrainBloomTuning.resolveDuration)) settle \(fmt(GrainBloomTuning.settleDuration)) reduce \(fmt(GrainBloomTuning.reduceDuration))",
            "stage \(fmt(GrainBloomTuning.stageWidth)) \(fmt(GrainBloomTuning.stageHeight)) lattice \(GrainBloomTuning.lattice)",
            "bayer4 \(GrainBloomTuning.bayer4.prefix(4).map(String.init).joined(separator: ","))",
            "bayer8 \(bayerRow())",
        ]
        lines += session(reduceMotion: false, tag: "f")
        lines += session(reduceMotion: true, tag: "r")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func bayerRow() -> String {
        (0..<8).map { String(GrainBloomMath.bayer8(row: 0, column: $0)) }.joined(separator: ",")
    }

    private static func session(reduceMotion: Bool, tag: String) -> [String] {
        var lines: [String] = []
        var index = 0
        func snap(_ model: GrainBloomModel) {
            lines.append(line(tag, index, model))
            index += 1
        }
        func run(_ model: inout GrainBloomModel, steps: Int) {
            for _ in 0..<steps {
                model.step(dt)
                snap(model)
            }
        }

        var model = GrainBloomModel(reduceMotion: reduceMotion)
        snap(model)
        model.setGenerating(true)
        lines.append("\(tag) e generating 1")
        snap(model)
        run(&model, steps: 3)
        model.setImagePresent(true)
        lines.append("\(tag) e image 1")
        snap(model)
        run(&model, steps: 16)
        model.replay()
        lines.append("\(tag) e replay")
        snap(model)
        run(&model, steps: 12)

        var cancel = GrainBloomModel(generating: true, reduceMotion: reduceMotion)
        cancel.setGenerating(false)
        lines.append("\(tag) e cancel \(cancel.phase.rawValue)")
        snap(cancel)

        var swap = GrainBloomModel(generating: false, hasImage: true, reduceMotion: reduceMotion)
        swap.setImagePresent(false)
        swap.setImagePresent(true)
        lines.append("\(tag) e swap \(swap.epoch) \(swap.phase.rawValue)")
        snap(swap)
        return lines
    }

    private static func line(_ tag: String, _ index: Int, _ model: GrainBloomModel) -> String {
        let blob = model.blob(0)
        return [
            tag,
            "\(index)",
            model.phase.rawValue,
            model.hasImage ? "1" : "0",
            "\(model.epoch)",
            fmt(model.phaseTime),
            fmt(model.resolveProgress),
            fmt(model.revealCoverage),
            fmt(model.cellSize),
            fmt(model.blur),
            fmt(model.shimmer),
            fmt(model.glint),
            fmt(blob.x),
            fmt(blob.y),
            "\"\(model.accessibilityValue)\"",
        ].joined(separator: " ")
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct GrainBloomGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = GrainBloomGoldenTrace.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: GrainBloomGoldenTrace.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: GrainBloomGoldenTrace.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: GrainBloomGoldenTrace.fixtureURL, encoding: .utf8)
        #expect(got == expected)
    }

    @Test func fullMotionCoverageEndsAtOneAndReduceMotionBlobsStayPut() throws {
        let text = GrainBloomGoldenTrace.make()
        let full = text.split(separator: "\n").filter { $0.hasPrefix("f ") && !$0.contains(" e ") }
        var previous = -1.0
        var epoch = -1
        for line in full {
            let fields = line.split(separator: " ")
            let lineEpoch = Int(fields[4]) ?? 0
            let coverage = Double(fields[7]) ?? 0
            if lineEpoch != epoch {
                epoch = lineEpoch
                previous = -1
            }
            #expect(coverage >= previous - 1e-9)
            previous = coverage
        }
        #expect(full.contains { $0.split(separator: " ")[7] == "1.00000000" })
        let reduced = text.split(separator: "\n").filter { $0.hasPrefix("r ") && !$0.contains(" e ") }
        let origin = GrainBloomMath.blob(index: 0, time: 0, reduceMotion: true)
        let originX = GrainBloomGoldenTrace.fmt(origin.x)
        let originY = GrainBloomGoldenTrace.fmt(origin.y)
        for line in reduced {
            let fields = line.split(separator: " ")
            #expect(fields[12] == Substring(originX))
            #expect(fields[13] == Substring(originY))
        }
    }
}
