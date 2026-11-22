import Foundation
import Testing
@testable import BoltStreakCore

/// Eight-decimal trace shared with `webports/boltstreak-core.mjs`.
/// `fmt` rounds half away from zero on the absolute value, matching the JS port.
enum BoltStreakGolden {
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
            "dt \(fmt(BoltStreakReel.dt))",
            "burn \(fmt(BoltStreakTuning.ignitionDuration)) frames \(BoltStreakTuning.burnFrames)",
            "cap \(fmt(BoltStreakTuning.maxFrame))",
            "length \(fmt(BoltPath.length))",
            "p0 \(point(BoltPath.sample(0)))",
            "p50 \(point(BoltPath.sample(0.5)))",
            "p100 \(point(BoltPath.sample(1)))",
            "mid \(point(BoltPath.sample(progress: 0.5, in: BoltStreakTuning.weeklyRect)))",
            "sin \(fmt(BoltStreakMath.sin(0))) \(fmt(BoltStreakMath.sin(BoltStreakMath.halfPi))) \(fmt(BoltStreakMath.sin(BoltStreakMath.pi)))",
            "week \(fmt(BoltStreakTuning.weeklyRect.x)) \(fmt(BoltStreakTuning.weeklyRect.y)) \(fmt(BoltStreakTuning.weeklyRect.width)) \(fmt(BoltStreakTuning.weeklyRect.height))",
            "days \(fmt(BoltStreakTuning.dayOriginX)) \(fmt(BoltStreakTuning.dayOriginY)) \(fmt(BoltStreakTuning.dayWidth)) \(fmt(BoltStreakTuning.dayHeight)) \(fmt(BoltStreakTuning.dayStride))",
            "glow \(fmt(BoltStreakTuning.glowSettled)) \(fmt(BoltStreakTuning.glowPulse)) \(fmt(BoltStreakTuning.glowOmega))",
            "tilt \(fmt(BoltStreakTuning.tiltDegrees)) \(fmt(BoltStreakTuning.tiltPerspective))",
            "reel \(BoltStreakReel.totalFrames) \(fmt(BoltStreakReel.duration))",
        ]
        lines += script()
        lines += reel()
        return lines.joined(separator: "\n") + "\n"
    }

    private static func point(_ p: Vec2) -> String { "\(fmt(p.x)) \(fmt(p.y))" }

    private static func script() -> [String] {
        var lines: [String] = []
        var model = BoltStreakModel(completed: [], today: .friday, reduceMotion: false)
        func snap(_ tag: String, _ current: BoltStreakModel) { lines.append("\(tag) \(body(current))") }
        func note(_ tag: String, _ events: [BoltStreakEvent]) {
            if events.isEmpty {
                lines.append("\(tag) e")
            } else {
                lines.append("\(tag) e \(events.map(describe).joined(separator: " "))")
            }
        }
        snap("s", model)
        note("s", model.ignite(.friday))
        snap("s", model)
        for _ in 0..<10 {
            note("s", model.step(BoltStreakReel.dt))
            snap("s", model)
        }
        note("s", model.ignite(.friday))
        note("s", model.ignite(.saturday))
        snap("s", model)
        var guardCount = 0
        while model.active == .friday && guardCount < 80 {
            note("s", model.step(BoltStreakReel.dt))
            guardCount += 1
        }
        snap("s", model)
        var reduced = BoltStreakModel(today: .friday, reduceMotion: true)
        note("r", reduced.igniteToday())
        snap("r", reduced)
        note("r", reduced.step(BoltStreakReel.dt))
        note("r", reduced.step(0.2))
        snap("r", reduced)
        return lines
    }

    private static func reel() -> [String] {
        var frames: [Int] = Array(0...8)
        let burnStart = BoltStreakReel.ignitionFrame(0)
        frames.append(contentsOf: burnStart...(burnStart + BoltStreakTuning.burnFrames + 2))
        frames.append(BoltStreakReel.ignitionFrame(3) - 4)
        frames.append(BoltStreakReel.ignitionFrame(3) + 18)
        frames.append(BoltStreakReel.ignitionFrame(6) + 18)
        frames.append(BoltStreakReel.reduceStart - 8)
        frames.append(BoltStreakReel.reduceStart + BoltStreakReel.reduceLead + 8)
        frames.append(BoltStreakReel.totalFrames - 8)
        return frames.map { frame in
            "f \(frame) \(body(BoltStreakReel.model(atFrame: frame)))"
        }
    }

    private static func body(_ model: BoltStreakModel) -> String {
        let progress = Weekday.allCases.map { fmt(model.dayProgress($0)) }.joined(separator: ",")
        let activeHead = model.active.flatMap { model.head(for: $0) }
        let weeklyHead = model.weeklyHead
        return [
            progress,
            fmt(model.weeklyProgress),
            fmt(model.weeklyTarget),
            fmt(model.active.map { model.glow(for: $0) } ?? 0),
            fmt(model.elapsed),
            model.active?.traceName ?? "-",
            "\(model.queue.count)",
            activeHead.map(point) ?? "- -",
            weeklyHead.map(point) ?? "- -",
            model.reduceMotion ? "1" : "0",
        ].joined(separator: " ")
    }

    private static func describe(_ event: BoltStreakEvent) -> String {
        switch event {
        case .tick: "tick"
        case .ignited(let day): "ignited \(day.traceName)"
        }
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-trace.txt")
    }
}

@Suite("Golden trace") struct BoltStreakGoldenTraceTests {
    @Test func fixtureMatchesTheCore() throws {
        let got = BoltStreakGolden.make()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: BoltStreakGolden.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try got.write(to: BoltStreakGolden.fixtureURL, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: BoltStreakGolden.fixtureURL, encoding: .utf8)
        #expect(got == expected)
        #expect(got.contains("p0 "))
        #expect(got.contains("p50 "))
        #expect(got.contains("p100 "))
        #expect(got.contains("s e ignited friday tick"))
        #expect(got.contains("s e"))
        #expect(got.contains("r e ignited friday tick"))
        #expect(got.contains(" f ") == false)
    }
}
